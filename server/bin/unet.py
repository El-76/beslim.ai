import cv2
import keras
import numpy
import segmentation_models
import tensorflow

def dice_coef(y_true, y_pred, smooth=1.0):
    y_true_f = keras.backend.flatten(y_true)
    y_pred_f = keras.backend.flatten(y_pred)
    intersection = keras.backend.sum(y_true_f * y_pred_f)

    return (2.0 * intersection + smooth) / (keras.backend.sum(y_true_f) + keras.backend.sum(y_pred_f) + smooth)

def dice_loss(y_true, y_pred, smooth=1):
    return (1.0 - dice_coef(y_true, y_pred, smooth))


def bce_dice_loss(y_true, y_pred):
    return keras.losses.binary_crossentropy(y_true, y_pred) + dice_loss(y_true, y_pred)

def load():
    global model
    model = segmentation_models.Unet(backbone_name='mobilenetv2', input_shape=(512, 800, 3), classes=3, encoder_freeze=True, weights=None)

    model.compile(optimizer=keras.optimizers.Adam(), loss=bce_dice_loss, metrics=[dice_coef])
    model.load_weights('/opt/beslim.ai/etc/unet_v1.h5')

def classify(data, session, graph, debug_files=None):
    decoded_image = cv2.imdecode(numpy.fromstring(data, numpy.uint8), cv2.IMREAD_COLOR)

    resized_image = cv2.cvtColor(cv2.resize(decoded_image, (800, 512)), cv2.COLOR_BGR2RGB)

    with graph.as_default():
        keras.backend.set_session(session)

        mask = model.predict_on_batch(numpy.array([resized_image.astype(numpy.float32) / 255.0]))[0]

    shape = (decoded_image.shape[1], decoded_image.shape[0])

    p = mask.mean(axis=(0, 1))

    threshold = 0.05

    min_x = shape[0]
    max_x = -1
    min_y = shape[1]
    max_y = -1

    if numpy.all(p < threshold):
       result = 'Unknown', []
    else:
       i = numpy.argmax(p)
       c = {0: 'Apple', 1: 'Hamburger', 2: 'Pizza'}[i]

       mask_image = (numpy.max(mask, axis=2) * 255.0).astype(numpy.uint8)

       resized_mask_image = cv2.resize(cv2.cvtColor(mask_image, cv2.COLOR_BGR2RGB), shape)

       resized_mask_image_gray = cv2.cvtColor(resized_mask_image, cv2.COLOR_BGR2GRAY)

       _, threshold = cv2.threshold(resized_mask_image_gray, 64, 64, 64)

       contours, hierarchy = cv2.findContours(threshold, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)

       for contour in contours:
           for x, y in [ (e[0][0], e[0][1]) for e in contour ]:
               min_x = min(x, min_x)
               max_x = max(x, max_x)
               min_y = min(y, min_y)
               max_y = max(y, max_y)

       if debug_files:
           cv2.imwrite(debug_files[0], decoded_image)

           resized_mask_image = cv2.drawContours(resized_mask_image, contours, -1, (255, 255, 255), 3, cv2.LINE_AA, hierarchy, 1)

           for center in [(min_x, (min_y + max_y) // 2), (max_x, (min_y + max_y) // 2), ((min_x + max_x) // 2, min_y), ((min_x + max_x) // 2, max_y)]:
               resized_mask_image = cv2.circle(resized_mask_image, center, 15, (0, 0, 255), -1) 

           cv2.imwrite(debug_files[1], resized_mask_image)

       result = c, [min_x, (min_y + max_y) // 2,  max_x, (min_y + max_y) // 2, (min_x + max_x) // 2, min_y, (min_x + max_x) // 2, max_y]

    return result
