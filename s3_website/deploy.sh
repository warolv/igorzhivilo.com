#!/bin/bash

docker run --rm \
    --name s3_website \
    -it \
    -v "$(cd .. && pwd):/app" \
    utils/s3_website \
    s3_website push