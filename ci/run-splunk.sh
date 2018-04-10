#!/usr/bin/env bash

/opt/splunk/bin/splunk start


while [ ! -f /opt/splunk/etc/apps/launcher/local/inputs.conf ]; do echo "Running..."; sleep 10;  done


/opt/splunk/bin/splunk stop