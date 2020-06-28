import os

#tf_devices = (('CPU', 0), ('GPU', 1),)
tf_devices = (('CPU', 0),)

os.environ["CUDA_VISIBLE_DEVICES"] = ",".join([str(g[1]) for g in tf_devices if g[0] == 'GPU'])
