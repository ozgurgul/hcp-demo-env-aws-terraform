#!/usr/bin/env bash

set -e # abort on error
set -u # abort on undefined variable

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/../../variables.sh"

MAPR_HOST=${MAPR_HOSTS_PRV_IPS[0]} # From variables.sh
MAPR_USER=ad_admin1
MAPR_TCKT=ad_admin1_impersonation_ticket
MAPR_TCKT_PATH=/tmp/${MAPR_TCKT}
MAPR_VMNT=/users
MAPR_CLUSTER_NAME=demo.mapr.com
MAPR_DTAP_NAME=ext-mapr

# 2 = EPIC Demo Tenant
TENANT_KEYTAB_DIR=/srv/bluedata/keytab/2/


ssh -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T ubuntu@${MAPR_HOST} << ENDSSH
	echo pass123 | maprlogin password -user ${MAPR_USER} -cluster ${MAPR_CLUSTER_NAME}
	maprlogin generateticket -type servicewithimpersonation -user ${MAPR_USER} -out maprfuseticket
ENDSSH

MAPRFUSETICKET=$(ssh -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T ubuntu@${MAPR_HOST} cat maprfuseticket)
echo MAPRFUSETICKET:${MAPRFUSETICKET}


ssh -o StrictHostKeyChecking=no -i "${LOCAL_SSH_PRV_KEY_PATH}" -T centos@${CTRL_PUB_IP} <<-SSH_EOF
	set -xeu

	# copy impresonation ticket to the tenant folder on the controller
	sudo echo $MAPRFUSETICKET > ${TENANT_KEYTAB_DIR}/${MAPR_TCKT}
	sudo chown centos:apache ${TENANT_KEYTAB_DIR}/${MAPR_TCKT}
	sudo chmod 660 ${TENANT_KEYTAB_DIR}/${MAPR_TCKT}

	command -v hpecp >/dev/null 2>&1 || { 
		echo >&2 "Ensure you have run: bin/experimental/install_hpecp_cli.sh"
		exit 1; 
	}

	set +u
	pyenv activate my-3.6.10 # installed by bin/experimental/install_hpecp_cli.sh
	set -u	
		
	# First we need 'admin' to setup the Demo Tenant authentication AD groups
	cat > ~/.hpecp.conf <<-CAT_EOF
		[default]
		api_host = ${CTRL_PRV_IP}
		api_port = 8080
		use_ssl = ${INSTALL_WITH_SSL}
		verify_ssl = False
		warn_ssl = False
		username = admin
		password = admin123
	CAT_EOF

	# set the log level for the HPE CP CLI 
	export LOG_LEVEL=DEBUG
		
	# test connectivity to HPE CP with the CLI
	hpecp license platform-id

	# setup AD user for tenant Administrator
	# NOTE:
	#  - /api/v1/role/2 = Admins
	#  - /api/v1/role/3 = Members
	cat >tenant_ad_auth.json<<-JSON_EOF
	{
		"external_user_groups": [
		    {
			"role": "/api/v1/role/2",
			"group":"CN=DemoTenantAdmins,CN=Users,DC=samdom,DC=example,DC=com"
		    },
		    {
			"role": "/api/v1/role/3",
			"group": "CN=DemoTenantUsers,CN=Users,DC=samdom,DC=example,DC=com"
		    }
		]
	}
	JSON_EOF
	hpecp httpclient put /api/v1/tenant/2?external_user_groups --json-file tenant_ad_auth.json

	# The datatap needs to be created as a tenant administrator, not as global admin
	cat > ~/.hpecp.conf <<-CAT_EOF
		[default]
		api_host = ${CTRL_PRV_IP}
		api_port = 8080
		use_ssl = ${INSTALL_WITH_SSL}
		verify_ssl = False
		warn_ssl = False
		username = ad_admin1
		password = pass123
	CAT_EOF

	cat >datatap.json<<-JSON_EOF
		{
		  "bdfs_root": {
		    "path_from_endpoint": "${MAPR_VMNT}"
		  },
		  "endpoint": {
		    "cluster_name": "${MAPR_CLUSTER_NAME}",
		    "ticket": "${MAPR_TCKT}",
		    "type": "mapr",
		    "secure": true,
		    "cldb": [
		      "${MAPR_HOSTS_PRV_IPS[0]}", "${MAPR_HOSTS_PRV_IPS[1]}"
		    ],
		    "ticket_type": "servicewithimpersonation",
		    "ticket_user": "${MAPR_USER}",
		    "mapr_tenant_volume": false,
		    "impersonation_enabled": true
		  },
		  "flags": {
		    "read_only": false
		  },
		  "label": {
		    "name": "${MAPR_DTAP_NAME}",
		    "description": "mapr volume global share"
		  }
		}
	JSON_EOF
	hpecp httpclient post /api/v1/dataconn --json-file datatap.json
SSH_EOF
