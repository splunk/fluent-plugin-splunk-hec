#!/usr/bin/env bash
set -e

echo "Pushing fluent-plugin-splunk-hec gem to rubygems.org..."
echo "gem `gem --version`"
cat .circleci/gem_credentials | sed -e "s/__RUBYGEMS_API_KEY__/${RUBYGEMS_API_KEY}/" > ~/.gem/credentials
chmod 0600 ~/.gem/credentials
#Reenable to push to ruby gems
#gem push /tmp/pkg/fluent-plugin-splunk-hec-*.gem