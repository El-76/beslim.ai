#!/bin/bash

cd `dirname $0`

PATH=/opt/atomic/atomic-protobuf/root/usr/bin/:${PATH}

protoc ../common/*.proto --proto_path=../common/ --python_out=./bin

docker build -t beslim.ai .
