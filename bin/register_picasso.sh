#!/usr/bin/env bash

set -e
set -o pipefail

if [[ -z $1 ]]; then
  echo Usage: $0 CLUSTER_ID
  echo Where: CLUSTER_ID = /api/v2/k8scluster/[0-9]*
  exit 1
fi

CLUSTER_ID=$1

set -u

source ./scripts/check_prerequisites.sh
source ./scripts/variables.sh

MASTERS=($(./bin/get_k8s_masters.sh $CLUSTER_ID))
echo MASTERS=${MASTERS[@]}

FIRST_MASTER_IP=$(./bin/get_k8s_host_ip.sh ${MASTERS[0]})
echo FIRST_MASTER_IP=$FIRST_MASTER_IP

ssh -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T centos@${CTRL_PUB_IP} << ENDSSH
  set =x
  export LOG_FILE_PATH=/tmp/register_k8s_prepare.log 
  export MASTER_NODE_IP="${FIRST_MASTER_IP}" 
  
  /opt/bluedata/bundles/hpe-cp-*/startscript.sh --action prepare_dftenants
ENDSSH

ssh -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T centos@${CTRL_PUB_IP} << ENDSSH
  set =x
  export LOG_FILE_PATH=/tmp/register_k8s_configure.log
  export MASTER_NODE_IP="${FIRST_MASTER_IP}"
  
  echo yes | /opt/bluedata/bundles/hpe-cp-*/startscript.sh --action configure_dftenants
ENDSSH

ssh -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T centos@${CTRL_PUB_IP} << ENDSSH
  sudo yum install -y expect
  
  set -x
  export SCRIPTNAME=\$(ls /opt/bluedata/bundles/hpe-cp-*/startscript.sh)
  export MASTER_NODE_IP=${FIRST_MASTER_IP}
  export LOG_FILE_PATH=/tmp/register_k8s_register.log
  
  
expect <<EOF

   set timeout 1800
  
   spawn \$SCRIPTNAME --action register_dftenants
   
   expect ".*Enter Site Admin username: " { send "admin\r" }
   expect "admin\r\nEnter Site Admin password: " { send "admin123\r" }
   expect eof
EOF

ENDSSH