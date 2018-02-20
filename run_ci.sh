#!/bin/sh

apk add --no-cache build-base jq-dev git \
  && bundle \
  && rake
