#!/bin/bash

# check for namespace
if [ -z "$1" ]
  then
    echo "No namespace passed"
    echo "usage: pixie-diag.sh <namespace>"
    exit 0
fi

# Timestamp
timestamp=$(date +"%Y%m%d%H%M%S")

# namespace variable
namespace=$1

# Create a log file
exec > >(tee -a "$PWD/pixie_diag_$timestamp.log") 2>&1

echo ""
echo "*****************************************************"
echo "Checking agent status"
echo "*****************************************************"
echo ""

# Check for px
if ! [ -x "$(command -v px)" ]; then
  echo 'Info: px (Pixie CLI) is not installed. Agent status report will be unavailable.' >&2
  echo 'You can install the Pixie CLI by running:' >&2
  echo 'bash -c "$(curl -fsSL https://withpixie.ai/install.sh)"' >&2
  else
  echo "Get agent status from Pixie"
  px run px/agent_status
  echo ""
  echo "Collect logs from Pixie"
  px collect-logs
fi

# Check HELM releases
echo ""
echo "*****************************************************"
echo "Checking HELM releases"
echo "*****************************************************"
echo ""

helm list -A -n $namespace

# Check System Info
echo ""
echo "*****************************************************"
echo "Key Information"
echo "*****************************************************"
echo ""

nodes=$(kubectl get nodes | awk '{print $1}' | tail -n +2)

# check node count
nodecount=$(kubectl get nodes --selector=kubernetes.io/hostname!=node_host_name | tail -n +2 | wc -l)
echo "Cluster has "$nodecount" nodes"

if [ $nodecount -gt 100 ]
  then
    echo "Node limit is greater than 100"
fi

# pods not running
podsnr=$(kubectl get pods -n $namespace -o go-template='{{ range  $item := .items }}{{ range .status.conditions }}{{ if (or (and (eq .type "PodScheduled") (eq .status "False")) (and (eq .type "Ready") (eq .status "False"))) }}{{ $item.metadata.name}} {{ end }}{{ end }}{{ end }}')

# count of pods not running
podsnrc=$(kubectl get pods -n $namespace -o go-template='{{ range  $item := .items }}{{ range .status.conditions }}{{ if (or (and (eq .type "PodScheduled") (eq .status "False")) (and (eq .type "Ready") (eq .status "False"))) }}{{ $item.metadata.name}} {{ end }}{{ end }}{{ end }}'| grep "^.*$" -c)

if [ $podsnrc -gt 0 ]
  then
    echo "There are $podsnrc pods not running!"
    echo "These pods are not running"
    echo $podsnr
fi

echo ""
echo "*****************************************************"
echo "Node Information"
echo "*****************************************************"

for node_name in $nodes
  do
    # Get K8s version and Kernel from nodes
    echo ""
    echo "System Info from $node_name"
    kubectl describe node $node_name | grep -i 'Kernel Version\|OS Image\|Operating System\|Architecture\|Container Runtime Version\|Kubelet Version'
    done

# Check Allocated resources Available/Consumed
echo ""
echo "*****************************************************"
echo "Checking Allocated resources Available/Consumed"
echo "*****************************************************"

for node_name in $nodes
  do
    # Get Allocated resources from nodes
    echo ""
    echo "Node Allocated resources info from $node_name"
    kubectl describe node $node_name | grep "Allocated resources" -A 9
  done

# Get kubectl describe node output for 3 nodes
echo ""
echo "*****************************************************"
echo "Collecting Node Detail (limited to 3 nodes)"
echo "*****************************************************"

nodedetailcounter=0
for node_name in $nodes
  do
    if [ $nodedetailcounter -lt 3 ]
    then
      # Get node detail from a sampling of nodes
      echo ""
      echo "Collecting node detail from $node_name"
      kubectl describe node $node_name
      let "nodedetailcounter+=1"
    else
      break
    fi
  done

# Get all Kubernetes resources in namespace
echo ""
echo "*****************************************************"
echo "Check all Kubernetes resources in namespace"
echo "*****************************************************"

# Get all api-resources in namespace
for i in $(kubectl api-resources --verbs=list -o name | grep -v "events.events.k8s.io" | grep -v "events" | sort | uniq);
do
echo ""
echo "Resource:" $i;
kubectl -n $namespace get --ignore-not-found ${i};
done

echo ""
echo "*****************************************************"
echo "Checking logs"
echo "*****************************************************"

deployments=$(kubectl get deployments -n $namespace | awk '{print $1}' | tail -n +2)

for deployment_name in $deployments
  do
    # Get logs from deployed
    echo ""
    echo "Logs from $deployment_name"
    kubectl logs --tail=50 deployments/$deployment_name -n $namespace
    done

echo ""
echo "*****************************************************"
echo "Checking pod events"
echo "*****************************************************"

pods=$(kubectl get pods -n $namespace | awk '{print $1}' | tail -n +2)

for pod_name in $pods
  do
    # Get events from pods in New Relic namespace
    echo ""
    echo "Events from pod name $pod_name"
    kubectl get events --all-namespaces --sort-by='.lastTimestamp'  | grep -i $pod_name
    done

echo ""
echo "*****************************************************"
echo "Checking Pixie Operator"
echo "*****************************************************"
echo ""
# Pixie Operator pod
popod=$(kubectl get pods -n px-operator -o=name |  grep pixie-operator)
echo "Logs from $popod"

# Get logs from operator pod
kubectl logs --tail=50 $popod -n px-operator

echo ""
echo "*****************************************************"
echo "Checking Vizier Operator"
echo "*****************************************************"
echo ""
# Vizier Operator pod
vopod=$(kubectl get pods -n px-operator -o=name |  grep vizier-operator)
echo "Logs from $vopod"

# Get logs from Vizier pod
kubectl logs --tail=50 $vopod -n px-operator

echo ""
echo "*****************************************************"


echo "File created = pixie_diag_<date>.log"
echo "File created = pixie_logs_<date>.zip"

echo ""
echo "*****************************************************"
echo ""
echo "End pixie-diag"
echo ""
