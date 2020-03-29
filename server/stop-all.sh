#!/bin/bash

docker stop `docker ps -f ancestor=beslim.ai -q`
