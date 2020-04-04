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

    product_classes = [segment_out_message.productClass for segment_out_message in message.segmentOutMessages]

    product_class = product_classes[0] if len(set(product_classes)) == 1 else 'Unknown'
    attempts = len(product_classes)
    if product_class == 'Hamburger':
        density = 100.0

        width = 0.0
        height = 0.0
        for i in range(0, len(message.distancesBetween), 2):
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
            for i, segment_out_message in enumerate(message.segmentOutMessages):
                f.write('SegmentOutMessage #{0:d}\n'.format(i))
                f.write('sessionId: {}\n'.format(segment_out_message.sessionId))
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
    attempt = flask.request.args.get('attempt', '0')
    model = flask.request.args.get('model', default_model)

    classify = models.get(model, {'classify': stub_classify})['classify']

    message = SegmentInMessage_pb2.SegmentInMessage()

    message.ParseFromString(flask.request.get_data(cache=False))

    image = message.photo

    if debug == '1':
        debug_orig_image_file = os.path.join(var_run_path, 'debug', '{}-{}.png'.format(session_id, attempt))
        debug_class_image_file = os.path.join(var_run_path, 'debug', '{}-{}-class.png'.format(session_id, attempt))

        debug_files = (debug_orig_image_file, debug_class_image_file)
    else:
        debug_files = None

    product_class, points_distances_between = classify(image, session, graph, debug_files=debug_files)

    message = SegmentOutMessage_pb2.SegmentOutMessage()

    message.sessionId = session_id
    message.productClass = product_class
    message.pointsDistancesBetween.extend(points_distances_between)

    return flask.Response(response=message.SerializeToString(), status=200, mimetype='application/x-protobuf')

@application.route('/ping', methods=['GET', 'POST'])
def ping():
    return 'Pong!'

if __name__ == '__main__':
    WSGIServer(application, bindAddress=('0.0.0.0', 7878)).run()
