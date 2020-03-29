#!/bin/bash

cd `dirname $0`

docker run -d --network beslim.ai --ip 172.88.0.2 -p7878:7878 -v `pwd`/debug/:/opt/beslim.ai/var/run/debug/ beslim.ai nginx -g 'daemon off;' | awk '{ print("nginx: "substr($0, 1, 12)) }'
