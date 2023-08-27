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

minikube image load splunk/fluentd-hec:recent

echo "Deploying k8s-connect with latest changes"
helm install ci-sck --set global.splunk.hec.token=$CI_SPLUNK_HEC_TOKEN \
--set global.splunk.hec.host=$CI_SPLUNK_HOST \
--set kubelet.serviceMonitor.https=true \
--set splunk-kubernetes-logging.image.tag=recent \
--set splunk-kubernetes-logging.image.pullPolicy=IfNotPresent \
-f ci_scripts/sck_values.yml helm-chart/splunk-connect-for-kubernetes
# kubectl get pod | grep "ci-sck-splunk-kubernetes-logging" | awk 'NR==1{print $1}
kubectl get pod
# wait for deployment to finish
# metric and logging deamon set for each node + aggr + object + splunk
PODS=$((MINIKUBE_NODE_COUNTS*2+2+1))
until kubectl get pod | grep Running | [[ $(wc -l) == $PODS ]]; do
   kubectl get pod
   sleep 2;
done
