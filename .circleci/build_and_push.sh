#!/usr/bin/env bash
set -e
aws ecr get-login --region $AWS_REGION --no-include-email | bash
echo "Building linux docker image..."
cp /tmp/pkg/fluent-plugin-splunk-hec-*.gem docker/linux
docker build --no-cache -t splunk/fluent-plugin-splunk-hec:ci ./docker/linux
docker tag splunk/fluent-plugin-splunk-hec:ci $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/k8s-ci-logging:latest
echo "Push docker image to ecr..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/k8s-ci-logging:latest | awk 'END{print}'
echo "Docker image pushed successfully."
