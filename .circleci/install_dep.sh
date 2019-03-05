#!/usr/bin/env bash
sudo gem update --system
gem install bundler
bundle update --bundler
bundle install