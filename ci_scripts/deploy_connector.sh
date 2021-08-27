#!/usr/bin/env bash
set -e

#Make sure to check and clean previously failed deployment
echo "Checking if previous deployment exist..."
if [ "`helm ls --short`" == "" ]; then
   echo "Nothing to clean, ready for deployment"
else
   helm delete $(helm ls --short)
fi

# Clone splunk-connect-for-kubernetes repo
cd /opt
git clone https://github.com/splunk/splunk-connect-for-kubernetes.git
cd splunk-connect-for-kubernetes

echo "Deploying k8s-connect with latest changes"
helm install ci-sck --set global.splunk.hec.token=$CI_SPLUNK_HEC_TOKEN \
--set global.splunk.hec.host=$CI_SPLUNK_HOST \
--set kubelet.serviceMonitor.https=true \
--set splunk-kubernetes-logging.image.repository=fluentd-hec \
--set splunk-kubernetes-logging.image.pullPolicy=IfNotPresent \
-f ci_scripts/sck_values.yml helm-chart/splunk-connect-for-kubernetes
#wait for deployment to finish
until kubectl get pod | grep Running | [[ $(wc -l) == 4 ]]; do
   sleep 1;
done