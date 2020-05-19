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
    response += '        <style> table.sessions-table, .sessions-table td { border: 1px solid black; padding: 5px; border-collapse: collapse; width: 100%; } </style>'
    response += '        <table class="sessions-table">\n'

    session_files = sorted(glob.glob(os.path.join(var_run_path, 'debug', '*.txt')))

    session_refs = {}

    all_files = glob.glob(os.path.join(var_run_path, 'debug', '*.png'))
    all_files += glob.glob(os.path.join(var_run_path, 'debug', '*.jpeg'))
    all_files += glob.glob(os.path.join(var_run_path, 'debug', '*.html'))
    for ref in sorted(all_files):
        for s in session_files:
            session = '.'.join(os.path.basename(s).split('.')[:-1])

            if os.path.basename(ref).startswith(session):
                refs = session_refs.get(session, [])

                refs += [ ref ]

                session_refs[session] = refs

                break


    for s in session_files:
        response += '            <tr>\n'

        session = '.'.join(os.path.basename(s).split('.')[:-1])

        response += ('                <td style="white-space:nowrap; width: 1%;">' + datetime.datetime.utcfromtimestamp(int(session.split('-')[0])).strftime('%Y-%m-%d %H:%M:%S') + '<br>' + session + '</td>\n')

        with open(s, 'r') as f:
            response += '                <td style="white-space:pre-wrap; word-wrap:break-word; width: 98%;">'

            response += f.read().rstrip()

            response += '</td>\n'

        response += '                <td style="white-space:nowrap; width: 1%;">\n'

        for ref in session_refs.get(session, []):
            response += ('<a href="/beslim.ai/debug/' + os.path.basename(ref) + '">' + os.path.basename(ref) + '</a><br>')

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

        product_class, point_pairs, mask_points, debug_image = (
            classify(decoded_image, snapshot.grid, session, graph, debug)
        )

        product_classes.append(product_class)

        nearest_pairs = []
        for i in range(0, len(point_pairs)):
            nearest_pairs.append(([None, None], [None, None]))

        for (y, x) in mask_points:
            for i, pair in enumerate(point_pairs):
                for j, point in enumerate(pair):
                    coords = snapshot.grid[y].row[x]

                    distance = (coords.vx - point[0]) ** 2 + (coords.vy - point[1]) ** 2
                    min_distance = nearest_pairs[i][j][0]
                    if min_distance is None or min_distance > distance:
                        nearest_pairs[i][j][0] = distance
                        nearest_pairs[i][j][1] = coords

        if debug:
            scale = 10.0


            world_point_index = {}
            mask_point_index = {}

            mask_mesh_points = []
            world_mesh_points = []

            im = 0
            iw = 0

            for y, row in enumerate(snapshot.grid):
                for x, coords in enumerate(row.row):
                    if (y, x) in mask_points:
                        mask_point_index[(y, x)] = im

                        im += 1

                        mask_mesh_points.append(
                            '{{x: {:.3f}, y: {:.3f}, z: {:.3f}}}'.format(
                                coords.x * scale, coords.y * scale, -coords.z * scale
                            )
                        )
                    else:
                        for y_ in range(max(0, y - 1), min(len(snapshot.grid), y + 2)):
                            for x_ in range(max(0, x - 1), min(len(row.row), x + 2)):
                                if (y_, x_) not in world_point_index:
                                    world_point_index[(y_, x_)] = iw

                                    coords_ = snapshot.grid[y_].row[x_]

                                    world_mesh_points.append(
                                        '{{x: {:.3f}, y: {:.3f}, z: {:.3f}}}'.format(
                                            coords_.x * scale, coords_.y * scale, -coords_.z * scale
                                        )
                                    )

                                    iw += 1


            mask_mesh_edges = []
            mask_mesh_polygons = []

            for y, row in enumerate(snapshot.grid):
                for x, coords in enumerate(row.row):
                    if (y, x) in mask_points:
                        debug_image = cv2.circle(debug_image, (coords.vx, coords.vy), 2, (255, 0, 0), -1)

                        if (y, x + 1) in mask_point_index:
                            mask_mesh_edges.append('{{a: {}, b: {}}}'.format(mask_point_index[(y, x)], mask_point_index[(y, x + 1)]));

                            if (y + 1, x) in mask_point_index and (y + 1, x + 1) in mask_point_index:
                                mask_mesh_polygons.append(
                                    '{{vertices: [{}, {}, {}, {}]}}'.format(
                                        mask_point_index[(y, x)],
                                        mask_point_index[(y, x + 1)],
                                        mask_point_index[(y + 1, x + 1)],
                                        mask_point_index[(y + 1, x)]
                                    )
                                );

                        if (y + 1, x) in mask_point_index:
                            mask_mesh_edges.append('{{a: {}, b: {}}}'.format(mask_point_index[(y, x)], mask_point_index[(y + 1, x)]))
                    else:
                        debug_image = cv2.circle(debug_image, (coords.vx, coords.vy), 2, (0, 255, 0), -1)

            mask_mesh_points_string = '[ ' + ', '.join(mask_mesh_points) + ' ]'
            mask_mesh_edges_string = '[ ' + ', '.join(mask_mesh_edges) + ' ]'
            mask_mesh_polygons_string = '[ ' + ', '.join(mask_mesh_polygons) + ' ]'


            world_mesh_edges = []
            world_mesh_polygons = []
            for y, row in enumerate(snapshot.grid):
                for x, coords in enumerate(row.row):
                    if (y, x) in world_point_index:
                        if (y, x + 1) in world_point_index:
                            a = 0
                            for j_ in range(-1, 2):
                                if (y + j_, x) in mask_point_index:
                                    a += 1

                                if (y + j_, x + 1) in mask_point_index:
                                    a += 1

                            if a < 6:
                                world_mesh_edges.append('{{a: {}, b: {}}}'.format(world_point_index[(y, x)], world_point_index[(y, x + 1)]));

                            if (y + 1, x) in world_point_index and (y + 1, x + 1) in world_point_index:
                                a = 0
                                for i_ in range(0, 2):
                                    for j_ in range(0, 2):
                                        if (y + j_, x + i_) in mask_point_index:
                                            a += 1

                                if a < 4:
                                    world_mesh_polygons.append(
                                        '{{vertices: [{}, {}, {}, {}]}}'.format(
                                            world_point_index[(y, x)],
                                            world_point_index[(y, x + 1)],
                                            world_point_index[(y + 1, x + 1)],
                                            world_point_index[(y + 1, x)]
                                        )
                                    )

                        if (y + 1, x) in world_point_index:
                            a = 0
                            for i_ in range(-1, 2):
                                if (y, x + i_) in mask_point_index:
                                    a += 1

                                if (y + 1, x + i_) in mask_point_index:
                                    a += 1

                            if a < 6:
                                world_mesh_edges.append('{{a: {}, b: {}}}'.format(world_point_index[(y, x)], world_point_index[(y + 1, x)]))

            world_mesh_points_string = '[' + ', '.join(world_mesh_points) + ']'
            world_mesh_edges_string = '[' + ', '.join(world_mesh_edges) + ']'
            world_mesh_polygons_string = '[' + ', '.join(world_mesh_polygons) + ']'


            threeD_view = os.path.join(var_run_path, 'debug', '{}-{:02d}.html'.format(session_id, attempt))
            with open(threeD_view, 'wt') as f:
                for line in threeD_view_template:
                    line = line.replace('##sessionId##', session_id)
                    line = line.replace('##attempt##', str(attempt))
                    line = line.replace('##worldPoints##', world_mesh_points_string)
                    line = line.replace('##worldEdges##', world_mesh_edges_string)
                    line = line.replace('##worldPolygons##', world_mesh_polygons_string)
                    line = line.replace('##maskPoints##', mask_mesh_points_string)
                    line = line.replace('##maskEdges##', mask_mesh_edges_string)
                    line = line.replace('##maskPolygons##', mask_mesh_polygons_string)
                    line = line.replace('##cameraX##', '{:.3f}'.format(snapshot.cameraX * scale))
                    line = line.replace('##cameraY##', '{:.3f}'.format(snapshot.cameraY * scale))
                    line = line.replace('##cameraZ##', '{:.3f}'.format(-snapshot.cameraZ * scale))
                    line = line.replace('##lookAtX##', '{:.3f}'.format(snapshot.lookAtX * scale))
                    line = line.replace('##lookAtY##', '{:.3f}'.format(snapshot.lookAtY * scale))
                    line = line.replace('##lookAtZ##', '{:.3f}'.format(-snapshot.lookAtZ * scale))
                    line = line.replace('##cameraUpX##', '{:.3f}'.format(snapshot.cameraUpX * scale))
                    line = line.replace('##cameraUpY##', '{:.3f}'.format(snapshot.cameraUpY * scale))
                    line = line.replace('##cameraUpZ##', '{:.3f}'.format(-snapshot.cameraUpZ * scale))
                    line = line.replace('##cameraFov##', '{:.3f}'.format(snapshot.cameraFov))
                    line = line.replace('##viewportWidth##', '{:d}'.format(decoded_image.shape[1]))
                    line = line.replace('##viewportHeight##', '{:d}'.format(decoded_image.shape[0]))

                    f.write(line)

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
    threeD_view_template = '/opt/beslim.ai/etc/3d-view.html.t'
    with open(threeD_view_template, 'rt') as f:
        threeD_view_template = f.readlines();

    WSGIServer(application, bindAddress=('0.0.0.0', 7878)).run()
