#!/bin/bash

cd `dirname $0`

if [ `docker info 2>/dev/null | fgrep Runtimes | fgrep -o nvidia` == "nvidia" ]; then
    RUNTIME="--runtime=nvidia"
else
    RUNTIME=""
fi

docker run $RUNTIME -d --network beslim.ai --ip 172.88.0.3 -v`pwd`/config.py:/opt/beslim.ai/bin/config.py:ro -v`pwd`/debug/:/opt/beslim.ai/var/run/debug/ beslim.ai /opt/beslim.ai/bin/server.fcgi | awk '{ print("fastcgi: "substr($0, 1, 12)) }'
