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
echo "Copying licenses to be included in the docker image..."
mkdir -p docker/licenses
cp -rp LICENSE docker/licenses/
docker build --no-cache -t splunk/fluentd-hec:$TAG ./docker
