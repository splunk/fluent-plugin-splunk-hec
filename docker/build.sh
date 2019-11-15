#!/usr/bin/env bash
set -e
TAG=$1

# Install dependecies
gem install bundler
bundle update --bundler
bundle install

# Build Gem
rake build -t -v
cp pkg/fluent-plugin-*.gem docker

# Build Docker Image
docker build --no-cache -t splunk/fluentd-hec:$TAG ./docker
