#!/bin/bash

cd `dirname "$0"`

./stop-all.sh

./build.sh

echo

./run-fastcgi.sh

./run-nginx.sh
