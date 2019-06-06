#!/usr/bin/env bash
export SHELL=/bin/bash
set -e
#Setting up python env to run integration tests
echo "Setting up environment..."
sudo apt-get update
sudo apt install python3-pip -y
sudo pip3 install pytest requests_unixsocket
echo "Running integration tests..."
python3 .circleci/integration/test.py