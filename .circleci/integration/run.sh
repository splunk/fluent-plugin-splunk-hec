#!/usr/bin/env bash
set -e
#Install and run fluentd-hec-plugin
gem install pkg/fluent-plugin-splunk-hec-*.gem
sudo mkdir /etc/fluent
sudo cp .circleci/integration/fluent.conf /etc/fluent/fluent.conf
sudo cp .circleci/integration/test_file.txt /etc/
nohup fluentd &
echo "wait for data ingestion to finish..."
sleep 100
sudo ps ax | grep -i 'fluentd' | grep -v grep | awk '{print $1}' | xargs kill -9 > /dev/null 2>&1