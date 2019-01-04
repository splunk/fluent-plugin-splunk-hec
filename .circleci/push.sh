#!/usr/bin/env bash
set -e
sudo apt-get install -y python-pip libpython-dev > /dev/null 2>&1
sudo pip install awscli
aws s3 cp pkg/fluent-plugin-splunk-hec-*.gem s3://circleci-k8s-fluentd-hec/