FROM centos:centos7.7.1908

WORKDIR /root

RUN yum install -y epel-release

RUN yum install -y libSM libXext libXrender nginx protobuf python36 unzip

RUN pip3 install h5py==2.10.0 keras==2.3.1 keras-applications==1.0.8 keras-preprocessing==1.1.0 numpy==1.18.1 pyyaml==5.3 scipy==1.4.1 six==1.14.0

RUN pip3 install absl-py==0.9.0 astor==0.8.1 gast==0.3.3 google-pasta==0.1.8 grpcio==1.27.2 markdown==3.2.1 protobuf==3.6.1 setuptools==45.2.0 tensorboard==1.14.0 tensorflow==1.14.0 tensorflow-estimator==1.14.0 termcolor==1.1.0 werkzeug==1.0.0 wheel==0.34.2 wrapt==1.12.0

RUN pip3 install PyWavelets==1.1.1 cycler==0.10.0 decorator==4.4.1 efficientnet==1.0.0 image-classifiers==1.0.0 imageio==2.8.0 kiwisolver==1.1.0 matplotlib==3.1.3 networkx==2.4 pillow==7.0.0 pyparsing==2.4.6 python-dateutil==2.8.1 scikit-image==0.16.2 segmentation-models==1.0.1

RUN pip3 install Jinja2==2.11.1 MarkupSafe==1.1.1 click==7.0 flask==1.1.1 itsdangerous==1.1.0

RUN pip3 install flup-py3==1.0.3

RUN pip3 install opencv-python==4.2.0.32

COPY Mask_RCNN-master.zip /root
RUN unzip Mask_RCNN-master.zip \
    && cd Mask_RCNN-master \
#    && pip3 install -r requirements.txt \
    && pip3 install IPython==7.13.0 Send2Trash==1.5.0 Shapely==1.7.0 Sphinx==2.4.4 alabaster==0.7.12 attrs==19.3.0 babel==2.8.0 backcall==0.1.0 bleach==3.1.3 certifi==2019.11.28 chardet==3.0.4 cython==0.29.15 defusedxml==0.6.0 docutils==0.16 entrypoints==0.3 idna==2.9 imagesize==1.2.0 imgaug==0.4.0 importlib-metadata==1.5.0 ipykernel==5.1.4 ipyparallel==6.2.4 ipython-genutils==0.2.0 ipywidgets==7.5.1 jedi==0.16.0 jsonschema==3.2.0 jupyter-client==6.1.0 jupyter-core==4.6.3 mistune==0.8.4 nbconvert==5.6.1 nbformat==5.0.4 nose==1.3.7 notebook==6.0.3 packaging==20.3 pandocfilters==1.4.2 parso==0.6.2 pexpect==4.8.0 pickleshare==0.7.5 prometheus-client==0.7.1 prompt-toolkit==3.0.4 ptyprocess==0.6.0 pygments==2.6.1 pyrsistent==0.15.7 pytz==2019.3 pyzmq==19.0.0 qtconsole==4.7.1 qtpy==1.9.0 requests==2.23.0 snowballstemmer==2.0.0 sphinxcontrib-applehelp==1.0.2 sphinxcontrib-devhelp==1.0.2 sphinxcontrib-htmlhelp==1.0.3 sphinxcontrib-jsmath==1.0.1 sphinxcontrib-qthelp==1.0.3 sphinxcontrib-serializinghtml==1.1.4 terminado==0.8.3 testpath==0.4.4 tornado==6.0.4 traitlets==4.3.3 urllib3==1.25.8 wcwidth==0.1.8 webencodings==0.5.1 widgetsnbextension==3.5.1 zipp==3.1.0 \
    && python3 setup.py install

RUN mkdir -p /opt/beslim.ai/{bin,etc,var/run/{debug,log,model/mrcnn},var/www/html}

COPY etc/* /opt/beslim.ai/etc/

RUN cat /opt/beslim.ai/etc/mask_rcnn_config_train_0022.h5.* > /opt/beslim.ai/etc/mask_rcnn_config_train_0022.h5 \
    && rm -f /opt/beslim.ai/etc/mask_rcnn_config_train_0022.h5.*
RUN cat /opt/beslim.ai/etc/unet_v1.h5.* > /opt/beslim.ai/etc/unet_v1.h5 \
    && rm -f /opt/beslim.ai/etc/unet_v1.h5.*

RUN ln -s /opt/beslim.ai/etc/beslim.ai.conf /etc/nginx/conf.d/beslim.ai.conf

COPY bin/* /opt/beslim.ai/bin/

RUN chmod u+x /opt/beslim.ai/bin/server.fcgi

EXPOSE 7878
