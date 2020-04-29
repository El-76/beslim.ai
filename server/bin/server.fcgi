#!/usr/bin/python3 -u

import cv2
import datetime
import flask
import glob
import imghdr
import keras
import math
import numpy
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
    return 'Unknown', []

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

    for image in sorted(
        glob.glob(os.path.join(var_run_path, 'debug', '*.png')) + glob.glob(os.path.join(var_run_path, 'debug', '*.jpeg'))
    ):
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

        response += ('                <td style="white-space:nowrap">' + datetime.datetime.utcfromtimestamp(int(session.split('-')[0])).strftime('%Y-%m-%d %H:%M:%S') + '<br>' + session + '</td>\n')

        with open(s, 'r') as f:
            response += '                <td style="white-space:pre-wrap; word-wrap:break-word">'

            response += f.read().rstrip()

            response += '</td>\n'

        response += '                <td style="white-space:nowrap">\n'

        for image in session_images.get(session, []):
            response += ('<a href="/beslim.ai/debug/' + os.path.basename(image) + '">' + os.path.basename(image) + '</a><br>')

        response += '                </td>\n'

        response += '            </tr>\n'

    response += '        </table>\n    </body>\n</html>'

    return response

@application.route('/weight', methods=['POST'])
def weight():
    model = flask.request.args.get('model', default_model)
    debug = (flask.request.args.get('debug', '0') == '1')

    message = WeightInMessage_pb2.WeightInMessage()

    message.ParseFromString(flask.request.get_data(cache=False))

    session_id = flask.request.args.get(
        'session_id', '{}-{}-{}'.format(int(time.time()), get_ip(), os.getpid())
    )

    classify = models.get(model, {'classify': stub_classify})['classify']

    start = int(time.time() * 1000.0)

    product_classes = []
    grid_point_pair_lists = []
    for attempt, snapshot in enumerate(message.snapshots):
        image_type = imghdr.what(None, snapshot.photo)

        decoded_image = cv2.imdecode(numpy.fromstring(snapshot.photo, numpy.uint8), cv2.IMREAD_COLOR)

        if debug:
            cv2.imwrite(
                os.path.join(var_run_path, 'debug', '{}-{:02d}.{}'.format(session_id, attempt, image_type)),
                decoded_image
            )

        product_class, point_pairs, filtered_grid, debug_image = (
            classify(decoded_image, snapshot.grid, session, graph, debug)
        )

        product_classes.append(product_class)

        if debug:
            for coords in snapshot.grid:
                debug_image = cv2.circle(debug_image, (coords.vx, coords.vy), 2, (255, 0, 0), -1) 

        nearest_pairs = []
        for i in range(0, len(point_pairs)):
            nearest_pairs.append(([None, None], [None, None]))

        for coords in filtered_grid:
            for i, pair in enumerate(point_pairs):
                for j, point in enumerate(pair):
                    distance = (coords.vx - point[0]) ** 2 + (coords.vy - point[1]) ** 2
                    min_distance = nearest_pairs[i][j][0]
                    if min_distance is None or min_distance > distance:
                        nearest_pairs[i][j][0] = distance
                        nearest_pairs[i][j][1] = coords

        for coords in filtered_grid:
            if debug:
                debug_image = cv2.circle(debug_image, (coords.vx, coords.vy), 2, (0, 255, 255), -1)

        grid_point_pairs = []
        for nearest_pair in nearest_pairs:
            if (nearest_pair[0][0] is not None) and (nearest_pair[1][0] is not None):
                grid_point_pairs.append((nearest_pair[0][1], nearest_pair[1][1]))

        grid_point_pair_lists.append(grid_point_pairs)

        if debug:
            for grid_point_pair in grid_point_pairs:
                for grid_point in grid_point_pair:
                    debug_image = cv2.circle(
                        debug_image, (grid_point.vx, grid_point.vy), 2, (255, 255, 0), -1
                    )

        if debug:
            cv2.imwrite(
                os.path.join(var_run_path, 'debug','{}-{:02d}-class.{}'.format(session_id, attempt, image_type)),
                debug_image
            )

    classified_at = int(time.time() * 1000.0)

    result_product_class = product_classes[0] if len(set(product_classes)) == 1 else 'Unknown'

    widths = []
    heights = []
    density = 100.0
    total_width = 0.0
    total_height = 0.0
    n = 0.0
    for product_class, grid_point_pairs in zip(product_classes, grid_point_pair_lists):
        if product_class == 'Hamburger':
            if len(grid_point_pairs) == 2:
                pair_w = grid_point_pairs[0]
                p1 = pair_w[0]
                p2 = pair_w[1]
                width = math.sqrt(
                    (p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2 + (p1.z - p2.z) ** 2
                )

                pair_h = grid_point_pairs[1]
                p1 = pair_h[0]
                p2 = pair_h[1]
                height = math.sqrt(
                    (p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2 + (p1.z - p2.z) ** 2
                )

                total_width += width
                total_height += height

                n += 1.0
            else:
                width = None
                height = None

            if debug:
                widths.append(width)
                heights.append(height)

        if n > 0:
            avg_width = total_width / n
            avg_height = total_height / n

            weight = (3.14 * avg_width * avg_width / 8.0) * avg_height * density * 1000.0
        else:
            weight = None

    if result_product_class != 'Hamburger':
        weight = None

    if debug:
        debug_file = os.path.join(var_run_path, 'debug', '{}.txt'.format(session_id))

        with open(debug_file, 'w') as f:
            f.write('session id: {}\n'.format(session_id))
            f.write('time: {0:.3f}s\n'.format((classified_at - start) / 1000.0))
            f.write('model: {}\n\n'.format(model))

            for attempt, (product_class, width, height) in enumerate(zip(product_classes, widths, heights)):
                f.write('attempt #{:02d}\n'.format(attempt))
                f.write('product class: {}\n'.format(product_class))
                f.write('width: ' + ('{0:.3f}'.format(width) if width else 'n/a') + '\n')
                f.write('height: ' + ('{0:.3f}'.format(height) if height else 'n/a') + '\n\n')

            f.write('product class: {}\n'.format(result_product_class))
            f.write('weight: ' + ('{0:.3f}\n'.format(weight) if weight else 'n/a'))

    message = WeightOutMessage_pb2.WeightOutMessage()

    message.productClass = result_product_class
    message.weight = weight if weight else -1.0

    return flask.Response(response=message.SerializeToString(), status=200, mimetype='application/x-protobuf')

@application.route('/ping', methods=['GET', 'POST'])
def ping():
    return 'Pong!'

if __name__ == '__main__':
    WSGIServer(application, bindAddress=('0.0.0.0', 7878)).run()

