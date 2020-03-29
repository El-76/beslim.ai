#!/bin/bash

cd `dirname $0`

/opt/atomic/atomic-protobuf/root/usr/bin/protoc ../common/*.proto --proto_path=../common/ --python_out=./bin

docker build -t beslim.ai .
