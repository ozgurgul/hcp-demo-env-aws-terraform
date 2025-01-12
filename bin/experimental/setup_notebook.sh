#!/bin/bash 

  set -e
  set -o pipefail


if [[ -z $1 ]]; then
  echo Usage: $0 TENANT_ID
  exit 1
fi

set -u

./scripts/check_prerequisites.sh
source ./scripts/variables.sh

# use the project's HPECP CLI config file
export HPECP_CONFIG_FILE="./generated/hpecp.conf"

export TENANT_ID=$1
echo $TENANT_ID

export NB_CLUSTER_NAME=nb
echo NB_CLUSTER_NAME=$NB_CLUSTER_NAME

export MLFLOW_CLUSTER_NAME=mlflow
echo MLFLOW_CLUSTER_NAME=$MLFLOW_CLUSTER_NAME

export TRAINING_CLUSTER_NAME=trainingengineinstance
echo TRAINING_CLUSTER_NAME=$TRAINING_CLUSTER_NAME

ssh -q -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T ubuntu@${RDP_PUB_IP} <<-EOF1

  set -e
  set -u 
  set -o pipefail

  export CLUSTER_ID=\$(hpecp tenant list --query "[?_links.self.href == '$TENANT_ID'] | [0] | [_links.k8scluster]" --output text)
  echo CLUSTER_ID=\$CLUSTER_ID
  
  export TENANT_NS=\$(hpecp tenant list --query "[?_links.self.href == '$TENANT_ID'] | [0] | [namespace]" --output text)
  echo TENANT_NS=\$TENANT_NS
  
  export AD_USER_ID=\$(hpecp user list --query "[?label.name=='ad_user1'] | [0] | [_links.self.href]" --output text | cut -d '/' -f 5)
  export AD_USER_SECRET_HASH=\$(python3 -c "import hashlib; print(hashlib.md5('\$AD_USER_ID-ad_user1'.encode('utf-8')).hexdigest())")
  export AD_USER_KC_SECRET="hpecp-kc-secret-\$AD_USER_SECRET_HASH"

  set +e
  kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) -n \$TENANT_NS get secret \$AD_USER_KC_SECRET
  if [[ $? == 0 ]]; then
    echo "Secret \$AD_USER_KC_SECRET exists - removing"
    kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) -n \$TENANT_NS delete secret \$AD_USER_KC_SECRET
  fi
  set -e

cat > ~/.hpecp_tenant.conf <<CAT_EOF
[default]
api_host = ${CTRL_PRV_IP}
api_port = 8080
use_ssl = ${INSTALL_WITH_SSL}
verify_ssl = False
warn_ssl = False

[tenant]
tenant = $TENANT_ID
username = ad_user1
password = pass123
CAT_EOF

cat ~/.hpecp_tenant.conf
	
export AD_USER_KUBECONFIG="\$(PROFILE=tenant HPECP_CONFIG_FILE=~/.hpecp_tenant.conf hpecp tenant k8skubeconfig | sed -z 's/\n/\\\n/g')"
# printf "AD_USER_KUBECONFIG=\$AD_USER_KUBECONFIG"

echo

export DATA_BASE64=\$(base64 -w 0 <<END
{
  "stringData": {
    "config": "\$AD_USER_KUBECONFIG"
  },
  "kind": "Secret",
  "apiVersion": "v1",
  "metadata": {
    "labels": {
      "kubedirector.hpe.com/username": "ad_user1",
      "kubedirector.hpe.com/userid": "\$AD_USER_ID",
      "kubedirector.hpe.com/secretType": "kubeconfig"
    },
    "namespace": "\$TENANT_NS",
    "name": "\$AD_USER_KC_SECRET"
  }
}
END
)

echo DATA_BASE64=\$DATA_BASE64

hpecp httpclient post \$CLUSTER_ID/kubectl <(echo -n '{"data":"'\$DATA_BASE64'","op":"create"}')


###
### Training Cluster
###

echo "Launching Training Cluster"
cat <<EOF_YAML | kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) -n \$TENANT_NS apply -f -

apiVersion: "kubedirector.hpe.com/v1beta1"
kind: "KubeDirectorCluster"
metadata: 
  name: "$TRAINING_CLUSTER_NAME"
  namespace: "\$TENANT_NS"
  labels: 
    description: ""
spec: 
  app: "training-engine"
  namingScheme: "CrNameRole"
  appCatalog: "local"
  connections: 
    secrets: 
      - \$AD_USER_KC_SECRET
  roles: 
    - 
      id: "LoadBalancer"
      members: 1
      resources: 
        requests: 
          cpu: "2"
          memory: "4Gi"
          nvidia.com/gpu: "0"
        limits: 
          cpu: "2"
          memory: "4Gi"
          nvidia.com/gpu: "0"
      #Note: "if the application is based on hadoop3 e.g. using StreamCapabilities interface, then change the below dtap label to 'hadoop3', otherwise for most applications use the default 'hadoop2'"
      podLabels: 
        hpecp.hpe.com/dtap: "hadoop2"
    - 
      id: "RESTServer"
      members: 1
      resources: 
        requests: 
          cpu: "2"
          memory: "4Gi"
          nvidia.com/gpu: "0"
        limits: 
          cpu: "2"
          memory: "4Gi"
          nvidia.com/gpu: "0"
      #Note: "if the application is based on hadoop3 e.g. using StreamCapabilities interface, then change the below dtap label to 'hadoop3', otherwise for most applications use the default 'hadoop2'"
      podLabels: 
        hpecp.hpe.com/dtap: "hadoop2"
    - 
      id: "controller"
      members: 1
      resources: 
        requests: 
          cpu: "2"
          memory: "4Gi"
          nvidia.com/gpu: "0"
        limits: 
          cpu: "2"
          memory: "4Gi"
          nvidia.com/gpu: "0"
      #Note: "if the application is based on hadoop3 e.g. using StreamCapabilities interface, then change the below dtap label to 'hadoop3', otherwise for most applications use the default 'hadoop2'"
      podLabels: 
        hpecp.hpe.com/dtap: "hadoop2"
EOF_YAML
   

###
### Jupyter Notebook
###

echo "Launching Jupyter Notebook as 'ad_user1' user"
cat <<EOF_YAML | kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) -n \$TENANT_NS apply -f -
apiVersion: "kubedirector.hpe.com/v1beta1"
kind: "KubeDirectorCluster"
metadata: 
  name: "$NB_CLUSTER_NAME"
  namespace: "\$TENANT_NS"
  labels: 
    "kubedirector.hpe.com/createdBy": "\$AD_USER_ID"
spec: 
  app: "jupyter-notebook"
  appCatalog: "local"
  connections:
    clusters:
      - $MLFLOW_CLUSTER_NAME
      - $TRAINING_CLUSTER_NAME
    secrets: 
      - hpecp-ext-auth-secret
      - mlflow-sc
      - \$AD_USER_KC_SECRET
  roles: 
    - 
      id: "controller"
      members: 1
      resources: 
        requests: 
          cpu: "2"
          memory: "4Gi"
          nvidia.com/gpu: "0"
        limits: 
          cpu: "2"
          memory: "4Gi"
          nvidia.com/gpu: "0"
      #Note: "if the application is based on hadoop3 e.g. using StreamCapabilities interface, then change the below dtap label to 'hadoop3', otherwise for most applications use the default 'hadoop2'"
      podLabels: 
        hpecp.hpe.com/dtap: "hadoop2"
EOF_YAML

EOF1


cat static/datatap.ipynb | ./bin/ssh_rdp_linux_server.sh "cat > datatap.ipynb"
cat static/wine-quality.csv | ./bin/ssh_rdp_linux_server.sh "cat > wine-quality.csv"


ssh -q -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T ubuntu@${RDP_PUB_IP} <<-EOF1

  set -e
  set -u 
  set -o pipefail

  export CLUSTER_ID=\$(hpecp tenant list --query "[?_links.self.href == '$TENANT_ID'] | [0] | [_links.k8scluster]" --output text)
  echo CLUSTER_ID=\$CLUSTER_ID
  
  export TENANT_NS=\$(hpecp tenant list --query "[?_links.self.href == '$TENANT_ID'] | [0] | [namespace]" --output text)
  echo TENANT_NS=\$TENANT_NS
  
  export AD_USER_ID\=$(hpecp user list --query "[?label.name=='ad_user1'] | [0] | [_links.self.href]" --output text | cut -d '/' -f 5)
  export AD_USER_SECRET_HASH=\$(python3 -c "import hashlib; print(hashlib.md5('\$AD_USER_ID-ad_user1'.encode('utf-8')).hexdigest())")
  export AD_USER_KC_SECRET="hpecp-kc-secret-\$AD_USER_SECRET_HASH"

  echo Waiting for Notebook to have state==configured
  
  COUNTER=0
  while [ \$COUNTER -lt 30 ]; 
  do
    STATE=\$(kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) \
                get kubedirectorcluster -n \$TENANT_NS $NB_CLUSTER_NAME -o 'jsonpath={.status.state}')
    echo STATE=\$STATE
    [[ \$STATE == "configured" ]] && break
    sleep 1m
    let COUNTER=COUNTER+1 
  done

  # Retrieve the notebook pod

  POD=\$(kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) \
    get pod -l kubedirector.hpe.com/kdcluster=$NB_CLUSTER_NAME -n \$TENANT_NS -o 'jsonpath={.items..metadata.name}')
    
  echo TENANT_NS=\$TENANT_NS
  echo POD=\$POD
  
  echo "Login to notebook to create home folders for ad_admin1 and ad_user1"
  
  kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) \
    exec -n \$TENANT_NS \$POD -- sudo su - ad_admin1
    
  kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) \
    exec -n \$TENANT_NS \$POD -- sudo su - ad_user1
  
  echo "Copying example files to notebook pods"
  
  kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) \
    cp --container app datatap.ipynb \$TENANT_NS/\$POD:/home/ad_admin1/datatap.ipynb
    
  kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) \
    cp --container app wine-quality.csv \$TENANT_NS/\$POD:/home/ad_admin1/wine-quality.csv

  kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) \
    cp --container app datatap.ipynb \$TENANT_NS/\$POD:/home/ad_user1/datatap.ipynb
    
  kubectl --kubeconfig <(hpecp k8scluster --id \$CLUSTER_ID admin-kube-config) \
    cp --container app wine-quality.csv \$TENANT_NS/\$POD:/home/ad_user1/wine-quality.csv

EOF1
