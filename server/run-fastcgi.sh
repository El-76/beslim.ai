#!/bin/bash

cd `dirname $0`

docker run -d --network beslim.ai --ip 172.88.0.3 -v `pwd`/debug/:/opt/beslim.ai/var/run/debug/ beslim.ai /opt/beslim.ai/bin/server.fcgi | awk '{ print("fastcgi: "substr($0, 1, 12)) }'
