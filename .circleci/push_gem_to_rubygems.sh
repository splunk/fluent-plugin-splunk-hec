#!/usr/bin/env bash
set -e
rake build -t -v
echo "Pushing metrics gem to rubygems.org..."
echo "gem `gem --version`"
cat .circleci/gem_credentials | sed -e "s/__RUBYGEMS_API_KEY__/${RUBYGEMS_API_KEY}/" > ~/.gem/credentials
chmod 0600 ~/.gem/credentials
gem push pkg/fluent-plugin-splunk-hec-*.gem