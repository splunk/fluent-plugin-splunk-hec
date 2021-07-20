#!/usr/bin/env bash
set -e
TAG=$1

# Install dependecies
gem install bundler
bundle update --bundler
bundle install

# Build Gem
bundle exec rake build -t -v
cp pkg/fluent-plugin-*.gem docker

# Build Docker Image
VERSION=`cat VERSION`
echo "Copying licenses to be included in the docker image..."
mkdir -p docker/licenses
cp -rp LICENSE docker/licenses/
docker build --no-cache --pull --build-arg VERSION=$VERSION -t splunk/fluentd-hec:$TAG ./docker
