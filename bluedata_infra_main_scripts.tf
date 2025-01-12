
resource "local_file" "ca-cert" {
  filename = "${path.module}/generated/ca-cert.pem"
  content =  var.ca_cert
}

resource "local_file" "ca-key" {
  filename = "${path.module}/generated/ca-key.pem"
  content =  var.ca_key
}


//////////////////// Utility scripts  /////////////////////

/// instance start/stop/status

locals {
  instance_id_controller  = module.controller.id
  instance_id_gateway     = module.gateway.id
  instance_id_nfs         = module.nfs_server.instance_id != null ? module.nfs_server.instance_id : ""
  instance_id_ad          = module.ad_server.instance_id != null ? module.ad_server.instance_id : ""
  instance_id_rdp         = module.rdp_server.instance_id != null ? module.rdp_server.instance_id : ""
  instance_id_rdp_linux   = module.rdp_server_linux.instance_id != null ? module.rdp_server_linux.instance_id : ""
  instance_id_workers     = join(" ", aws_instance.workers.*.id)
  instance_id_workers_gpu = join(" ", aws_instance.workers_gpu.*.id)
  instance_id_mapr_cls_1  = join(" ", aws_instance.mapr_cluster_1_hosts.*.id)
  instance_id_mapr_cls_2  = join(" ", aws_instance.mapr_cluster_2_hosts.*.id)
  instance_ids = join(" ", [
    local.instance_id_nfs,
    local.instance_id_ad,
    local.instance_id_rdp,
    local.instance_id_rdp_linux,
    local.instance_id_controller,
    local.instance_id_gateway,
    local.instance_id_workers,
    local.instance_id_workers_gpu,
    local.instance_id_mapr_cls_1,
    local.instance_id_mapr_cls_2
   ])
}

resource "local_file" "cli_stop_ec2_instances" {
  filename = "${path.module}/generated/cli_stop_ec2_instances.sh"
  content =  <<-EOF
    #!/bin/bash
    echo "Deprecated.  Please use ./bin/ec2_stop_all_instances.sh"
  EOF
}

resource "local_file" "cli_stop_ec2_gpu_instances" {
  filename = "${path.module}/generated/cli_stop_ec2_gpu_instances.sh"
  content =  <<-EOF
    #!/bin/bash
    echo "Deprecated.  Please use ./bin/ec2_stop_worker_gpu_instances.sh"
  EOF
}

resource "local_file" "cli_stop_ec2_mapr_clus_1_instances" {
  filename = "${path.module}/generated/cli_stop_ec2_mapr_clus_1_instances.sh"
  content =  <<-EOF
    echo "Deprecated.  Use ./bin/ec2_stop_mapr_clus1_instances.sh"
  EOF
}


resource "local_file" "cli_start_ec2_instances" {
  filename = "${path.module}/generated/cli_start_ec2_instances.sh"
  content = <<-EOF
    echo "Deprecated.  Use ./bin/ec2_start_all_instances.sh"
  EOF
}

resource "local_file" "cli_start_ec2_gpu_instances" {
  filename = "${path.module}/generated/cli_start_ec2_gpu_instances.sh"
  content = <<-EOF
    echo "Deprecated.  Use ./bin/ec2_start_gpu_instances.sh"
  EOF
}


resource "local_file" "cli_running_ec2_instances" {
  filename = "${path.module}/generated/cli_running_ec2_instances.sh"
  content = <<-EOF
    #!/bin/bash
    echo "Deprecated. Please use ./bin/ec2_instance_status.sh"
  EOF  
}


resource "local_file" "cli_running_ec2_instances_all_regions" {
  filename = "${path.module}/generated/cli_running_ec2_instances_all_regions.sh"
  content = <<-EOF
    #!/bin/bash
    export AWS_DEFAULT_REGION=${var.region}
    for region in `aws ec2 describe-regions --output text | cut -f4`; do
      echo -e "\nListing Running Instances in region:'$region' ... matching '${local.user}' ";
      aws ec2 describe-instances --query "Reservations[*].Instances[*].{IP:PublicIpAddress,ID:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[0].Value}" --filters Name=instance-state-name,Values=running --output=table --region $region | grep -i ${local.user}
    done
  EOF  
}

resource "local_file" "ssh_controller_port_forwards" {
  filename = "${path.module}/generated/ssh_controller_port_forwards.sh"
  content = <<-EOF
    #!/bin/bash

    source "${path.module}/scripts/variables.sh"

    if [[ -e "${path.module}/etc/port_forwards.sh" ]]
    then
      PORT_FORWARDS=$(cat "${path.module}/etc/port_forwards.sh")
    else
      echo ./etc/port_forwards.sh file not found please create it and add your rules, e.g.
      echo cp ./etc/port_forwards.sh_template ./etc/port_forwards.sh
      exit 1
    fi
    echo Creating port forwards from "${path.module}/etc/port_forwards.sh"

    ssh -o StrictHostKeyChecking=no \
      -i "${var.ssh_prv_key_path}" \
      -N \
      centos@$CTRL_PUB_IP \
      $PORT_FORWARDS \
      "$@"
  EOF
}

resource "local_file" "ssh_controller" {
  filename = "${path.module}/generated/ssh_controller.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$CTRL_PUB_IP "$@"
  EOF
}

resource "local_file" "ssh_controller_private" {
  filename = "${path.module}/generated/ssh_controller_private.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$CTRL_PRV_IP "$@"
  EOF
}

resource "local_file" "ssh_gateway" {
  filename = "${path.module}/generated/ssh_gateway.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$GATW_PUB_IP "$@"
  EOF
}

resource "local_file" "ssh_ad" {
  filename = "${path.module}/generated/ssh_ad.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$AD_PUB_IP "$@"
  EOF
}

resource "local_file" "ssh_worker" {
  count = var.worker_count

  filename = "${path.module}/generated/ssh_worker_${count.index}.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$${WRKR_PUB_IPS[${count.index}]} "$@"
  EOF
}

resource "local_file" "ssh_worker_gpu" {
  count = var.gpu_worker_count

  filename = "${path.module}/generated/ssh_worker_gpu_${count.index}.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$${WRKR_GPU_PUB_IPS[${count.index}]} "$@"
  EOF
}

resource "local_file" "ssh_mapr_cluster_1_host" {
  count = var.mapr_cluster_1_count

  filename = "${path.module}/generated/ssh_mapr_cluster_1_host_${count.index}.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" ubuntu@$${MAPR_CLUSTER1_HOSTS_PUB_IPS[${count.index}]} "$@"
  EOF
}

resource "local_file" "ssh_mapr_cluster_2_host" {
  count = var.mapr_cluster_2_count

  filename = "${path.module}/generated/ssh_mapr_cluster_2_host_${count.index}.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" ubuntu@$${MAPR_CLUSTER2_HOSTS_PUB_IPS[${count.index}]} "$@"
  EOF
}

resource "local_file" "ssh_workers" {
  count = var.worker_count
  filename = "${path.module}/generated/ssh_worker_all.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     if [[ $# -lt 1 ]]
     then
        echo "You must provide at least one command, e.g."
        echo "./generated/ssh_worker_all.sh CMD1 CMD2 CMDn"
        exit 1
     fi

     for HOST in $${WRKR_PUB_IPS[@]}; 
     do
      ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$HOST "$@"
     done
  EOF
}

resource "local_file" "ssh_all" {
  count = var.worker_count
  filename = "${path.module}/generated/ssh_all.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     if [[ $# -lt 1 ]]
     then
        echo "You must provide at least one command, e.g."
        echo "./generated/ssh_worker_all.sh CMD1 CMD2 CMDn"
        exit 1
     fi

     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$CTRL_PUB_IP "$@"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$GATW_PUB_IP "$@"
     for HOST in $${WRKR_PUB_IPS[@]};
     do
        ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$HOST "$@"
     done
  EOF
}


resource "local_file" "wireshark_on_mac" {
  filename = "${path.module}/generated/wireshark_on_mac.sh"
  content = <<-EOF
  #!/bin/bash
    
  if [[ "$EUID" != "0" ]]; then
    echo "This script must be run as root - e.g. with sudo" 
    exit 1
  fi

  USER_BEFORE_SUDO=$(who am i | awk '{print $1}')

  echo Wireshark filter examples:
  echo --------------------------
  echo http
  echo http.request.method == "POST" or http.request.method == "GET"
  echo http.request.uri == "/api/v1/user"
  echo http.request.uri matches "k8skubeconfig"  
  echo --------------------------

  sudo -u $USER_BEFORE_SUDO ./generated/ssh_controller.sh sudo yum install -y -q tcpdump 
  sudo -u $USER_BEFORE_SUDO ./generated/ssh_controller.sh sudo tcpdump -i lo -U -s0 -w - 'port 8080' | sudo /Applications/Wireshark.app/Contents/MacOS/Wireshark -k -i -
  EOF
}

resource "local_file" "mcs_credentials" {
  filename = "${path.module}/generated/mcs_credentials.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     echo 
     echo ==== MCS Credentials ====
     echo 
     echo IP Addr:  $CTRL_PUB_IP
     echo Username: admin
     echo Password: $(ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$CTRL_PUB_IP "cat /opt/bluedata/mapr/conf/mapr-admin-pass")
     echo
  EOF
}

resource "local_file" "fix_restart_auth_proxy" {
  filename = "${path.module}/generated/fix_restart_auth_proxy.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$CTRL_PUB_IP 'docker restart $(docker ps | grep "epic/authproxy" | cut -d " " -f1); docker ps'
  EOF
}

resource "local_file" "fix_restart_webhdfs" {
  filename = "${path.module}/generated/fix_restart_webhdfs.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" centos@$CTRL_PUB_IP 'docker restart $(docker ps | grep "epic/webhdfs" | cut -d " " -f1); docker ps'
  EOF
}

resource "local_file" "platform_id" {
  filename = "${path.module}/generated/platform_id.sh"
  content = <<-EOF
     #!/bin/bash
     source "${path.module}/scripts/variables.sh"
     curl -s -k https://$CTRL_PUB_IP:8080/api/v1/license | python3 -c 'import json,sys;obj=json.load(sys.stdin);print (obj["uuid"])'
  EOF
}

resource "local_file" "rdp_windows_credentials" {
  filename = "${path.module}/generated/rdp_credentials.sh"
  count = var.rdp_server_enabled == true && var.rdp_server_operating_system == "WINDOWS" ? 1 : 0
  content = <<-EOF
    #!/bin/bash
    source "${path.module}/scripts/variables.sh"

    if grep -q 'OPENSSH' "${var.ssh_prv_key_path}"
    then
      echo "***** ERROR ******"
      echo "Found OPENSSH key but need RSA key at ${var.ssh_prv_key_path}"
      echo "You can convert with:"
      echo "$ ssh-keygen -p -N '' -m pem -f '${var.ssh_prv_key_path}'"
      echo "******************"
      exit 1
    fi

    echo 
    echo ==== RDP Credentials ====
    echo 
    echo IP Addr:  ${module.rdp_server.public_ip}
    echo URL:      "rdp://full%20address=s:${module.rdp_server.public_ip}:3389&username=s:Administrator"
    echo Username: Administrator
    echo -n "Password: "
    aws --region ${var.region} \
        --profile ${var.profile} \
        ec2 get-password-data \
        "--instance-id=${module.rdp_server.instance_id}" \
        --query 'PasswordData' | sed 's/\"\\r\\n//' | sed 's/\\r\\n\"//' | base64 -D | openssl rsautl -inkey "${var.ssh_prv_key_path}" -decrypt
    echo
    echo
  EOF
}

resource "local_file" "rdp_linux_credentials" {
  filename = "${path.module}/generated/rdp_credentials.sh"
  content = <<-EOF
    echo "Deprecated.  Use ./bin/rdp_credentials.sh"
  EOF
}

resource "local_file" "rdp_over_ssh" {
  filename = "${path.module}/generated/rdp_over_ssh.sh"
  count = var.rdp_server_enabled == true && var.rdp_server_operating_system == "LINUX" ? 1 : 0
  content = <<-EOF
    #!/bin/bash
    source "${path.module}/scripts/variables.sh"
    echo "Portforwarding 3389 on 127.0.0.1 to RDP Server [CTRL-C to cancel]"
    ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" ubuntu@$RDP_PUB_IP "$@" -L3389:localhost:3389 -N
  EOF
}

resource "local_file" "rdp_post_setup" {
  filename = "${path.module}/generated/rdp_post_provision_setup.sh"
  count = var.rdp_server_enabled == true && var.rdp_server_operating_system == "LINUX" ? 1 : 0
  content = <<-EOF
    #!/bin/bash
    source "${path.module}/scripts/variables.sh"
    ssh -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" ubuntu@$RDP_PUB_IP "sudo fastdd"  
  EOF
}

resource "local_file" "ssh_rdp_linux" {
  filename = "${path.module}/generated/ssh_rdp_linux_server.sh"
  content =  <<-EOF
    #!/bin/bash
    echo "Deprecated.  Please use ./bin/ssh_rdp_linux_server.sh"
  EOF
}

resource "local_file" "sftp_rdp_linux" {
  filename = "${path.module}/generated/sftp_rdp_linux_server.sh"
  count = var.rdp_server_enabled == true && var.rdp_server_operating_system == "LINUX" ? 1 : 0
  content = <<-EOF
    #!/bin/bash
    source "${path.module}/scripts/variables.sh"
    sftp -o StrictHostKeyChecking=no -i "${var.ssh_prv_key_path}" ubuntu@$RDP_PUB_IP    
  EOF
}

resource "local_file" "whatismyip" {
  filename = "${path.module}/generated/whatismyip.sh"

  content = <<-EOF
     #!/bin/bash
     echo $(curl -s http://ipinfo.io/ip)/32
  EOF
}

resource "local_file" "vpn_server_setup" {
  filename = "${path.module}/generated/vpn_server_setup.sh"
  count = var.rdp_server_enabled == true && var.rdp_server_operating_system == "LINUX" ? 1 : 0
  content  = <<-EOF
    #!/bin/bash
    echo "This script has been moved to the './bin' folder"
  EOF
}

resource "local_file" "vpn_mac_connect" {
  filename = "${path.module}/generated/vpn_mac_connect.sh"
  count = var.rdp_server_enabled == true && var.rdp_server_operating_system == "LINUX" ? 1 : 0
  content  = <<-EOF
    #!/bin/bash
    echo "This script has been moved to the './bin' folder"
  EOF
}

resource "local_file" "vpn_mac_delete" {
  filename = "${path.module}/generated/vpn_mac_delete.sh"
  count = var.rdp_server_enabled == true && var.rdp_server_operating_system == "LINUX" ? 1 : 0
  content  = <<-EOF
    #!/bin/bash

    set -e # abort on error
    set -u # abort on undefined variable

    source "${path.module}/scripts/variables.sh"
  
    if [[ "$EUID" != "0" ]]; then
      echo "This script must be run as root - e.g. with sudo" 
      exit 1
    fi

    macosvpn delete --name hpe-container-platform-aws || true # ignore error
    route -n delete -net $(terraform output subnet_cidr_block) $(terraform output softether_rdp_ip) || true # ignore error
  EOF
}

resource "local_file" "vpn_mac_status" {
  filename = "${path.module}/generated/vpn_mac_status.sh"
  count = var.rdp_server_enabled == true && var.rdp_server_operating_system == "LINUX" ? 1 : 0
  content  = <<-EOF
    #!/bin/bash

    set -e # abort on error
    set -u # abort on undefined variable

    source "${path.module}/scripts/variables.sh"
  
    if [[ "$EUID" != "0" ]]; then
      echo "This script must be run as root - e.g. with sudo" 
      exit 1
    fi

    VPN_STATUS="'$(scutil --nc list | grep hpe-container-platform-aws)'"
    if [[ "$VPN_STATUS" == "''" ]]; then
      echo "VPN not found."
    else
      echo "$VPN_STATUS"
    fi
  EOF
}

resource "local_file" "get_public_endpoints" {
  filename = "${path.module}/generated/get_public_endpoints.sh"
  content  = <<-EOF
    #!/usr/bin/env bash

    echo "Deprecated.  Please use ./bin/ec2_instance_status.sh"
  EOF
}

resource "local_file" "get_private_endpoints" {
  filename = "${path.module}/generated/get_private_endpoints.sh"
  content  = <<-EOF
    #!/usr/bin/env bash

    echo "Deprecated.  Please use ./bin/ec2_instance_status.sh"
  EOF
}
