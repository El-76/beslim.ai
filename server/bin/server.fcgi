#!/usr/bin/python3 -u

import datetime
import flask
import glob
import keras
import os
import socket
import tensorflow
import time

from flup.server.fcgi import WSGIServer

import config
import maskrcnn
import unet

import SegmentInMessage_pb2
import SegmentOutMessage_pb2
import WeightInMessage_pb2
import WeightOutMessage_pb2

def stub_load():
    pass

def stub_classify(data, session, graph, debug_files=None):
    pass

application = flask.Flask(__name__)

var_run_path = '/opt/beslim.ai/var/run/'

models = {
    'unet': {'load': unet.load, 'classify': unet.classify},
    'mrcnn': {'load': maskrcnn.load, 'classify': maskrcnn.classify}
}

default_model = 'mrcnn'


cpus = sorted(tensorflow.config.experimental.list_physical_devices('CPU'))
gpus = sorted(tensorflow.config.experimental.list_physical_devices('GPU'))

print('Tensorflow CPUs: ' + ', '.join([d.name for d in cpus]))
print('Tensorflow GPUs: ' + ', '.join([d.name for d in gpus]))

tf_visible_devices = []

if config.tf_devices:
    for tf_device in config.tf_devices:
        if tf_device[0] == 'CPU':
            tf_visible_devices.append(cpus[tf_device[1]])

        if tf_device[0] == 'GPU':
            gpu = gpus[tf_device[1]]

            tf_visible_devices.append(gpu)

            tensorflow.config.experimental.set_memory_growth(gpu, True)
else:
    if len(gpus) > 0:
        tf_visible_devices = gpus

        for gpu in gpus:
            tensorflow.config.experimental.set_memory_growth(gpu, True)
    else:
        tf_visible_devices = cpus

print('Tensorflow visible devices: ' + ', '.join([d.name for d in tf_visible_devices]))

tensorflow.config.experimental.set_visible_devices(tf_visible_devices)


session = tensorflow.compat.v1.Session()
graph = tensorflow.compat.v1.get_default_graph()

keras.backend.set_session(session)

for m in models:
    load = models.get(m, {'load': stub_load})['load']

    load()

def get_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # doesn't even have to be reachable
        s.connect(('10.255.255.255', 1))
        ip = s.getsockname()[0]
    except:
        ip = '127.0.0.1'
    finally:
        s.close()

    return ip

@application.route('/sessions', methods=['GET'])
def sessions():
    response = '<html>\n    <body>\n'
    response += '        <style> table.sessions-table, .sessions-table td { border: 1px solid black; padding: 5px; border-collapse: collapse; } </style>'
    response += '        <table class="sessions-table">\n'

    session_files = sorted(glob.glob(os.path.join(var_run_path, 'debug', '*.txt')))

    session_images = {}

    for image in sorted(glob.glob(os.path.join(var_run_path, 'debug', '*.png'))):
        for s in session_files:
            session = '.'.join(os.path.basename(s).split('.')[:-1])

            if os.path.basename(image).startswith(session):
                images = session_images.get(session, [])

                images += [ image ]

                session_images[session] = images

                break


    for s in session_files:
        response += '            <tr>\n'

        session = '.'.join(os.path.basename(s).split('.')[:-1])

        response += ('                <td>' + datetime.datetime.utcfromtimestamp(int(session.split('-')[0])).strftime('%Y-%m-%d %H:%M:%S') + '<br>' + session + '</td>\n')

        with open(s, 'r') as f:
            response += '                <td style="white-space:pre-wrap; word-wrap:break-word">'

            response += f.read().rstrip()

            response += '</td>\n'

        response += '                <td>\n'

        for image in session_images.get(session, []):
            response += ('<a href="/beslim.ai/debug/' + os.path.basename(image) + '">' + os.path.basename(image) + '</a><br>')

        response += '                </td>\n'

        response += '            </tr>\n'

    response += '        </table>\n    </body>\n</html>'

    return response

@application.route('/weight', methods=['POST'])
def weight():
    session_id = flask.request.args.get('session_id')
    debug = flask.request.args.get('debug', '0')

    message = WeightInMessage_pb2.WeightInMessage()

    message.ParseFromString(flask.request.get_data(cache=False))

    segment_out_messages = message.segmentOutMessages

    product_classes = [segment_out_message.productClass for segment_out_message in segment_out_messages.messages]

    product_class = product_classes[0] if len(set(product_classes)) == 1 else 'Unknown'
    attempts = len(product_classes)
    if product_class == 'Hamburger':
        density = 100.0

        width = 0.0
        height = 0.0
        for i in range(0, len(message.distancesBetween), 2):
            # TODO: check for -1.0
            width += message.distancesBetween[i]
            height += message.distancesBetween[i + 1]

        width /= attempts
        height /= attempts

        weight = (3.14 * width * width / 8.0) * height * density * 1000.0
    else:
        weight = -1.0

    if session_id and debug == '1':
        debug_file = os.path.join(var_run_path, 'debug', '{}.txt'.format(session_id))

        with open(debug_file, 'w') as f:
            f.write('SegmentOutMessages\n')
            f.write('sessionId: {}\n'.format(segment_out_messages.sessionId))
            f.write('time: {0:.3f}s\n\n'.format(segment_out_messages.time / 1000.0))

            for i, segment_out_message in enumerate(message.segmentOutMessages.messages):
                f.write('SegmentOutMessage #{0:d}\n'.format(i))
                f.write('productClass: {}\n'.format(segment_out_message.productClass))
                f.write('pointsDistancesBetween: ' + ', '.join(['{0:d}'.format(x) for x in segment_out_message.pointsDistancesBetween]) + '\n\n')

            f.write('WeightInMessage\n')
            f.write('distancesBetween: ' + ', '.join(['{0:.3f}'.format(x) for x in message.distancesBetween]) + '\n\n')

            f.write('WeightOutMessage\n')
            f.write('productClass: {}\n'.format(product_class))
            f.write('weight: {0:.3f}\n'.format(weight))

    message = WeightOutMessage_pb2.WeightOutMessage()

    message.productClass = product_class
    message.weight = weight

    return flask.Response(response=message.SerializeToString(), status=200, mimetype='application/x-protobuf')

@application.route('/segment', methods=['POST'])
def segment():
    session_id = flask.request.args.get('session_id', '{}-{}-{}'.format(int(time.time()), get_ip(), os.getpid()))
    debug = flask.request.args.get('debug', '0')
    model = flask.request.args.get('model', default_model)

    classify = models.get(model, {'classify': stub_classify})['classify']

    messages = SegmentInMessage_pb2.SegmentInMessages()

    messages.ParseFromString(flask.request.get_data(cache=False))

    start = int(time.time() * 1000.0)

    classification_result = []
    for attempt, message in enumerate(messages.messages):
        image = message.photo

        if debug == '1':
            debug_orig_image_file = os.path.join(var_run_path, 'debug', '{}-{}.png'.format(session_id, attempt))
            debug_class_image_file = os.path.join(var_run_path, 'debug', '{}-{}-class.png'.format(session_id, attempt))

            debug_files = (debug_orig_image_file, debug_class_image_file)
        else:
            debug_files = None

        product_class, points_distances_between = classify(image, session, graph, debug_files=debug_files)

        classification_result.append((product_class, points_distances_between,))

    duration = int(time.time() * 1000.0) - start

    messages = SegmentOutMessage_pb2.SegmentOutMessages()

    messages.sessionId = session_id

    m = []
    for product_class, points_distances_between in classification_result:
        message = SegmentOutMessage_pb2.SegmentOutMessage()

        message.productClass = product_class
        message.pointsDistancesBetween.extend(points_distances_between)

        m.append(message)

    messages.time = duration
    messages.model = model

    messages.messages.extend(m)

    return flask.Response(response=messages.SerializeToString(), status=200, mimetype='application/x-protobuf')

@application.route('/ping', methods=['GET', 'POST'])
def ping():
    return 'Pong!'

if __name__ == '__main__':
    WSGIServer(application, bindAddress=('0.0.0.0', 7878)).run()

