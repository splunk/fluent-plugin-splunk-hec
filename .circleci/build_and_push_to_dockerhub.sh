#!/usr/bin/env bash
set -e
echo "Building docker image..."
cp /tmp/pkg/fluent-plugin-splunk-hec-*.gem docker
VERSION=`cat VERSION`
docker build --no-cache -t splunk/fluent-plugin-splunk-hec:ci ./docker
docker tag splunk/fluent-plugin-splunk-hec:ci splunk/${DOCKERHUB_REPO_NAME}:${VERSION}
echo "Push docker image to splunk dockerhub..."
docker login --username=$DOCKERHUB_ACCOUNT_ID --password=$DOCKERHUB_ACCOUNT_PASS
docker push splunk/${DOCKERHUB_REPO_NAME}:${VERSION} | awk 'END{print}'
echo "Docker image pushed successfully to docker-hub."