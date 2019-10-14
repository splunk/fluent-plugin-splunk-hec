#!/usr/bin/env bash
set -e
sudo apt-get update
sudo apt-get install -y python-pip libpython-dev > /dev/null 2>&1
echo "Installing aws cli..."
sudo pip install awscli > /dev/null 2>&1
echo "Push fluentd-splunk-hec-plugin gem to s3..."
aws s3 cp /tmp/pkg/fluent-plugin-splunk-hec-*.gem s3://k8s-ci-artifacts/