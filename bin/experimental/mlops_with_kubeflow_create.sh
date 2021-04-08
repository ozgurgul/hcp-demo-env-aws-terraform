#!/bin/bash 

set -e
set -u

if [[ ! -d generated ]]; then
   echo "This file should be executed from the project directory"
   exit 1
fi

./scripts/check_prerequisites.sh
source ./scripts/variables.sh

pip3 install --quiet --upgrade --user hpecp

# use the project's HPECP CLI config file
export HPECP_CONFIG_FILE="./generated/hpecp.conf"

# Test CLI is able to connect
echo "Platform ID: $(hpecp license platform-id)"

set +u

MLFLOW_CLUSTER_NAME=mlflow
NB_CLUSTER_NAME=nb
AD_SERVER_PRIVATE_IP=$AD_PRV_IP

MASTER_IDS="${@:1:1}"  # FIRST ARGUMENT
WORKER_IDS=("${@:2}")  # REMAINING ARGUMENTS

echo "${MASTER_IDS}"
echo "${WORKER_IDS[@]}"

if [[ $MASTER_IDS =~ ^\/api\/v2\/worker\/k8shost\/[0-9]$ ]] && [[ ${WORKER_IDS[0]} =~ ^\/api\/v2\/worker\/k8shost\/[0-9]$ ]]; 
then
   echo 
else
   echo "Usage: $0 /api/v2/worker/k8shost/[0-9] /api/v2/worker/k8shost/[0-9] [ ... /api/v2/worker/k8shost/NNN ]"
   exit 1
fi

K8S_HOST_CONFIG="$(echo $MASTER_IDS | sed 's/ /:master,/g'):master,$(echo ${WORKER_IDS[@]} | sed 's/ /:worker,/g'):worker"
echo K8S_HOST_CONFIG=$K8S_HOST_CONFIG

set -u

K8S_VERSION=$(hpecp k8scluster k8s-supported-versions --major-filter 1 --minor-filter 20 --output text)

echo "Creating k8s cluster with version ${K8S_VERSION} and addons=[kubeflow] | timeout=1800s"
CLUSTER_ID=$(hpecp k8scluster create \
  --name c1 \
  --k8s-version "$K8S_VERSION" \
  --k8shosts-config "$K8S_HOST_CONFIG" \
  --addons ["kubeflow"] \
  --ext_id_svr_bind_pwd "5ambaPwd@" \
  --ext_id_svr_user_attribute "sAMAccountName" \
  --ext_id_svr_bind_type "search_bind" \
  --ext_id_svr_bind_dn "cn=Administrator,CN=Users,DC=samdom,DC=example,DC=com" \
  --ext_id_svr_host "${AD_SERVER_PRIVATE_IP}" \
  --ext_id_svr_group_attribute "memberOf" \
  --ext_id_svr_security_protocol "ldaps" \
  --ext_id_svr_base_dn "CN=Users,DC=samdom,DC=example,DC=com" \
  --ext_id_svr_verify_peer false \
  --ext_id_svr_type "Active Directory" \
  --ext_id_svr_port 636 \
  --external-groups '["CN=DemoTenantAdmins,CN=Users,DC=samdom,DC=example,DC=com","CN=DemoTenantUsers,CN=Users,DC=samdom,DC=example,DC=com"]')

echo "$CLUSTER_ID"

hpecp k8scluster wait-for-status --id $CLUSTER_ID --status [ready] --timeout-secs 3600
echo "K8S cluster created successfully - ID: ${CLUSTER_ID}"

echo "Adding addon [kubeflow] | timeout=1800s"
hpecp k8scluster add-addons --id $CLUSTER_ID --addons [kubeflow]
hpecp k8scluster wait-for-status --id $CLUSTER_ID --status [ready] --timeout-secs 1800
echo "Addon successfully added"

echo "Creating tenant"
TENANT_ID=$(hpecp tenant create --name "k8s-tenant-1" --description "dev tenant" --k8s-cluster-id $CLUSTER_ID  --tenant-type k8s --features '{ ml_project: true }' --quota-cores 1000)
hpecp tenant wait-for-status --id $TENANT_ID --status [ready] --timeout-secs 1800
echo "K8S tenant created successfully - ID: ${TENANT_ID}"

TENANT_NS=$(hpecp tenant get $TENANT_ID | grep "^namespace: " | cut -d " " -f 2)
echo TENANT_NS=$TENANT_NS

ADMIN_GROUP="CN=DemoTenantAdmins,CN=Users,DC=samdom,DC=example,DC=com"
ADMIN_ROLE=$(hpecp role list  --query "[?label.name == 'Admin'][_links.self.href] | [0][0]" --output json | tr -d '"')
hpecp tenant add-external-user-group --tenant-id "$TENANT_ID" --group "$ADMIN_GROUP" --role-id "$ADMIN_ROLE"

MEMBER_GROUP="CN=DemoTenantUsers,CN=Users,DC=samdom,DC=example,DC=com"
MEMBER_ROLE=$(hpecp role list  --query "[?label.name == 'Member'][_links.self.href] | [0][0]" --output json | tr -d '"')
hpecp tenant add-external-user-group --tenant-id "$TENANT_ID" --group "$MEMBER_GROUP" --role-id "$MEMBER_ROLE"

ADMIN_ID=$(hpecp user list --query "[?label.name=='admin'] | [0] | [_links.self.href]" --output text | cut -d '/' -f 5)

echo "Configured tenant with AD groups Admins=DemoTenantAdmins... and Members=DemoTenantUsers..."

export SECRET_HASH=$(python3 -c "import hashlib; print(hashlib.md5('$ADMIN_ID-admin'.encode('utf-8')).hexdigest())")
export KC_SECRET="hpecp-kc-secret-$SECRET_HASH"

ssh -q -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T ubuntu@${RDP_PUB_IP} <<-EOF1

  set -x

   echo TENANT_NS=$TENANT_NS
   echo SECRET_HASH=$SECRET_HASH
   echo KC_SECRET=$KC_SECRET
   
export DATA_BASE64=$(base64 -w 0 <<END
{
  "stringData": {
    "config": "\$(hpecp k8scluster --id $CLUSTER_ID admin-kube-config)"
  },
  "kind": "Secret",
  "apiVersion": "v1",
  "metadata": {
    "labels": {
      "kubedirector.hpe.com/username": "admin",
      "kubedirector.hpe.com/userid": "$ADMIN_ID",
      "kubedirector.hpe.com/secretType": "kubeconfig"
    },
    "namespace": "$TENANT_NS",
    "name": "$KC_SECRET"
  }
}
END
)

   hpecp httpclient post $CLUSTER_ID/kubectl <(echo -n '{"data":"'\$DATA_BASE64'","op":"create"}')
   
###
### MLFLOW Secret
###

echo "Creating MLFLOW secret"
cat <<EOF_YAML | kubectl --kubeconfig <(hpecp k8scluster --id $CLUSTER_ID admin-kube-config) -n $TENANT_NS apply -f -
apiVersion: v1 
data: 
  MLFLOW_ARTIFACT_ROOT: czM6Ly9tbGZsb3c= #s3://mlflow 
  AWS_ACCESS_KEY_ID: YWRtaW4= #admin 
  AWS_SECRET_ACCESS_KEY: YWRtaW4xMjM= #admin123 
kind: Secret
metadata: 
  name: mlflow-sc 
  labels: 
    kubedirector.hpe.com/secretType: mlflow 
type: Opaque 
EOF_YAML

###
### MLFLOW Cluster
###

echo "Launching MLFLOW Cluster"
cat <<EOF_YAML | kubectl --kubeconfig <(hpecp k8scluster --id $CLUSTER_ID admin-kube-config) -n $TENANT_NS apply -f -
apiVersion: "kubedirector.hpe.com/v1beta1"
kind: "KubeDirectorCluster"
metadata: 
  name: "$MLFLOW_CLUSTER_NAME"
  namespace: "$TENANT_NS"
  labels: 
    description: "mlflow"
spec: 
  app: "mlflow"
  namingScheme: "CrNameRole"
  appCatalog: "local"
  connections:
    secrets:
      - mlflow-sc
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

###
### Jupyter Notebook
###

echo "Launching Jupyter Notebook as 'admin' user"
cat <<EOF_YAML | kubectl --kubeconfig <(hpecp k8scluster --id $CLUSTER_ID admin-kube-config) -n $TENANT_NS apply -f -
apiVersion: "kubedirector.hpe.com/v1beta1"
kind: "KubeDirectorCluster"
metadata: 
  name: "$NB_CLUSTER_NAME"
  namespace: "$TENANT_NS"
  labels: 
    "kubedirector.hpe.com/createdBy": "$ADMIN_ID"
spec: 
  app: "jupyter-notebook"
  appCatalog: "local"
  connections: 
    secrets: 
      - hpecp-ext-auth-secret
      - mlflow-sc
      - $KC_SECRET 
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

export CLUSTER_ID=$CLUSTER_ID
export NB_CLUSTER_NAME=$NB_CLUSTER_NAME
export TENANT_NS=$TENANT_NS

./bin/experimental/setup_notebook.sh

