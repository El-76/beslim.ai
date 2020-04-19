import cv2
import keras
import numpy
import tensorflow

from mrcnn.config import Config
from mrcnn.model import MaskRCNN
from mrcnn.visualize import apply_mask

class ConfigInference(Config):
    NAME = 'config_inference'
    GPU_COUNT = 1
    IMAGES_PER_GPU = 1
    NUM_CLASSES = 4
    IMAGE_MAX_DIM = 384
    BATCH_SIZE = 1

def load():
    global model
    model = MaskRCNN(mode='inference', config=ConfigInference(), model_dir='/opt/beslim.ai/var/run/model/mrcnn')

    model.load_weights('/opt/beslim.ai/etc/mask_rcnn_config_train_0022.h5', by_name=True)

def classify(decoded_image, grid, session, graph, debug=False):
    with graph.as_default():
        keras.backend.set_session(session)

        detection_result = model.detect([cv2.cvtColor(decoded_image, cv2.COLOR_BGR2RGB)], verbose=0)[0]

    class_ids = detection_result['class_ids']
    rois = detection_result['rois']
    masks = detection_result['masks']

    shape = (decoded_image.shape[1], decoded_image.shape[0])

    center_x = -1
    min_x = shape[0]
    max_x = -1
    center_y = -1
    min_y = shape[1]
    max_y = -1

    if len(class_ids) == 1:
        c = {0: 'Unknown', 1: 'Apple', 2: 'Hamburger', 3: 'Pizza'}[class_ids[0]]
        
        if c == 'Unknown':
            point_pairs = []
            filtered_grid = []
        else:
            filtered_grid = []
            for coords in grid:
                if masks[coords.vy][coords.vx][0]:
                    filtered_grid.append(coords)

            bbox = rois[0]
            center_x = (bbox[1] + bbox[3]) // 2
            center_y = (bbox[0] + bbox[2]) // 2

            for x in range(min(bbox[1], bbox[3]), max(bbox[1], bbox[3])):
                if masks[center_y][x][0]:
                    if x < min_x:
                        min_x = x

                    if x > max_x:
                        max_x = x

            for y in range(min(bbox[0], bbox[2]), max(bbox[0], bbox[2])):
                if masks[y][center_x][0]:
                    if y < min_y:
                        min_y = y

                    if y > max_y:
                        max_y = y

            point_pairs = [((min_x, center_y),  (max_x, center_y)), ((center_x, min_y), (center_x, max_y))]
    else:
        c = 'Unknown'
        point_pairs = []
        filtered_grid = []

    if debug:
        masked_image = decoded_image

        for i, roi in enumerate(rois):
            cv2.rectangle(masked_image, (roi[1], roi[0]), (roi[3], roi[2]), (0, 255, 0), 2)

            apply_mask(masked_image, masks[:, :, i], (0, 255, 0))

            for pair in point_pairs:
               for center in pair:
                   masked_image = cv2.circle(masked_image, center, 15, (0, 0, 255), -1)
    else:
        masked_image = None

    return c, point_pairs, filtered_grid, masked_image
