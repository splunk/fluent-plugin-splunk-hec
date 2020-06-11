#!/usr/bin/env bash
set -e
bundle exec rake build
echo "Building docker image..."
cp pkg/fluent-plugin-splunk-hec-*.gem docker
echo "Copying licenses to be included in the docker image..."
mkdir docker/licenses
cp -rp LICENSE docker/licenses/
VERSION=`cat VERSION`
docker build --no-cache -t splunk/fluent-plugin-splunk-hec:ci ./docker
docker tag splunk/fluent-plugin-splunk-hec:ci splunk/${DOCKERHUB_REPO_NAME}:${VERSION}
docker tag splunk/fluent-plugin-splunk-hec:ci splunk/${DOCKERHUB_REPO_NAME}:latest
echo "Push docker image to splunk dockerhub..."
docker login --username=$DOCKERHUB_ACCOUNT_ID --password=$DOCKERHUB_ACCOUNT_PASS
docker push splunk/${DOCKERHUB_REPO_NAME}:${VERSION} | awk 'END{print}'
docker push splunk/${DOCKERHUB_REPO_NAME}:latest | awk 'END{print}'
echo "Docker image pushed successfully to docker-hub."
