#!/usr/bin/dumb-init /bin/sh

set -e

exec fluentd "$@"