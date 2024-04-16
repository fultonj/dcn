#!/usr/bin/env bash
# Import an image into the default and AZn locations
# Boot an instance and create a volume in the default location
# Boot an instance and create a volume in the AZn location
# -------------------------------------------------------
# VARS
OCP_AUTH=0
SHOW_CMD=1

OVERVIEW=0
GLANCE_SANITY=0
GLANCE_DEL=0
MULTI_GLANCE=0
CINDER_DEL=0
CINDER=0
VOL_FROM_IMAGE=0
CINDER_AZN=0
NOVA_CONTROL_LOGS=0
NOVA_COMPUTE_LOGS=0
PRINET=0
VM_DEL=0
VM=0
CONSOLE=0
VM_AZN=0
PET=0
CEPH_REPORT=0

# Set "n"
# 1 for AZ1 xor 2 for AZ2
NUM=1
AZ="az${NUM}"

if [ $NUM -eq 1 ]; then
    BEG=3
fi
if [ $NUM -eq 2 ]; then
    BEG=6
fi

CIR=cirros-0.5.2-x86_64-disk.img
CIR_URL=http://download.cirros-cloud.net/0.5.2/$CIR
IMG_NAME=cirros
VOL_NAME=vol1
VOL_IMG_NAME="${VOL_NAME}-${IMG_NAME}"
VM_NAME=vm1

if [ $VM_AZN -eq 1 ]; then
    VM_NAME=$VM_NAME-$AZ
fi
if [ $CINDER_AZN -eq 1 ]; then
    VOL_NAME=$VOL_NAME-$AZ
    VOL_IMG_NAME=$VOL_IMG_NAME-$AZ
fi
if [ $PET -eq 1 ]; then
    VM_NAME=$VM_NAME-pet
fi

SSH_OPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# -------------------------------------------------------
# FUNCTIONS

openstack() {
    # Run openstack command inside openstackclient pod
    if [ $SHOW_CMD -eq 1 ]; then
        echo ""
        echo "$ openstack $@"
    fi
    oc rsh -t --shell='/bin/sh' openstackclient openstack $@
    if [ $SHOW_CMD -eq 1 ]; then
        echo "$"
        echo ""
    fi
}

glance() {
    # Run glance command inside openstackclient pod
    # From opentsackclient pod's `.config/openstack/clouds.yaml`
    if [ $SHOW_CMD -eq 1 ]; then
        echo ""
        echo "$ glance $@"
    fi
    END=https://keystone-public-openstack.apps.ocp.openstack.lab
    oc rsh -t --shell='/bin/sh' openstackclient glance --os-auth-url $END --os-project-name admin --os-username admin --os-password 12345678 --os-user-domain-name default --os-project-domain-name default $@
    if [ $SHOW_CMD -eq 1 ]; then
        echo "$"
        echo ""
    fi
}

rceph() {
    # "Remote Ceph": run commands on remote ceph clusters
    NULL="2> /dev/null"
    local N="$1"
    local CMD="$2"
    shift
    shift
    if [ $N -eq 0 ]; then
        NODE="compute-0"
        FSID_ARG=""
    else
        # using global $BEG
        NODE="compute-$BEG"
        # They passed $NUM so we use $AZ
        FSID=$(ssh $SSH_OPT $NODE "sudo grep fsid /etc/ceph/$AZ.conf | sed 's/fsid = //'")
        FSID_ARG="--fsid $FSID"
    fi
    echo "Running \"$CMD $@\" on $NODE"
    echo "---"
    ssh $SSH_OPT $NODE "hostname; sudo cephadm shell $FSID_ARG -- $CMD $@ $NULL"
    echo ""
}

# -------------------------------------------------------
# MAIN(s)

if [ $OCP_AUTH -eq 1 ]; then
    export PASS=$(cat ~/.kube/kubeadmin-password)
    oc login -u kubeadmin -p $PASS https://api.ocp.openstack.lab:6443
    if [[ $? -gt 0 ]]; then
        exit 1
    fi
fi

if [ $OVERVIEW -eq 1 ]; then
    openstack endpoint list
    openstack network agent list
    openstack compute service list
    openstack aggregate list
    openstack aggregate show $AZ

    echo "Volume services"
    openstack volume service list

    echo "Compute availability zones"
    openstack availability zone list --compute

    echo "Volume availability zones"
    openstack availability zone list --volume
fi

if [ $GLANCE_SANITY -eq 1 ]; then
    glance image-list
    if [[ $? -gt 0 ]]; then
        echo "Aborting. Not even 'glance image-list' works."
        exit 1
    fi
fi

if [ $GLANCE_DEL -eq 1 ]; then
    echo "Ensuring there are no Glance images"
    glance image-list
    for IMG in $(SHOW_CMD=0 openstack image list -c ID -f value); do
        # had issue with new lines, so cleaning
        ID=$(echo $IMG | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
        openstack image delete $ID
    done
    glance image-list
fi

if [ $MULTI_GLANCE -eq 1 ]; then
    # import an image two the default store and one of the DCN stores
    glance stores-info
    # stage glance image on openstack client pod
    oc rsh -t --shell='/bin/sh' openstackclient stat $CIR > /dev/null 2>&1
    if [ $? -gt 0 ]; then
        oc rsh -t --shell='/bin/sh' openstackclient curl -L $CIR_URL -o $CIR
    fi
    echo "Uploading $CIR to az0 (default)"
    glance image-create \
           --disk-format raw \
           --container-format bare \
           --name $IMG_NAME \
           --file $CIR \
           --store az0
    for IMG in $(SHOW_CMD=0 openstack image list -c ID -f value); do
        # this loop should only run once, also clean whitespace from the UUID
        ID=$(echo $IMG | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
        echo "$CIR should only be on AZ0"
        glance image-show $ID | grep stores
        rceph 0 rbd -p images ls -l
        rceph $NUM rbd -p images ls -l
        echo "Importing $CIR to $AZ"
        glance image-import $ID --stores $AZ --import-method copy-image
        glance image-show $ID | grep stores
        rceph $NUM rbd -p images ls -l
    done
fi

if [ $CINDER_DEL -eq 1 ]; then
    echo "Ensuring there are no Cinder volumes"
    openstack volume list
    for IMG in $(SHOW_CMD=0 openstack volume list -c ID -f value); do
        # had issue with new lines, so cleaning
        ID=$(echo $IMG | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
        openstack volume delete $ID
    done
    openstack volume list
fi

if [ $CINDER -eq 1 ]; then
    if [ $CINDER_AZN -eq 1 ]; then
        echo "$AZ"
    else
        echo "DEFAULT"
    fi
    echo " --------- Ceph cinder volumes pool --------- "
    if [ $CINDER_AZN -eq 1 ]; then
        rceph $NUM rbd -p volumes ls -l
    else
        rceph 0 rbd -p volumes ls -l
    fi
    openstack volume list
    if [ $VOL_FROM_IMAGE -eq 1 ]; then
        echo "Creating 8 GB Cinder volume from $IMG_NAME"
        for IMG in $(SHOW_CMD=0 openstack image list -c ID -f value); do
            # this loop should only run once, also clean whitespace from the UUID
            ID=$(echo $IMG | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
        done
        if [ $CINDER_AZN -eq 1 ]; then
            openstack volume create --size 8 $VOL_IMG_NAME --image $ID --availability-zone $AZ
        else
            openstack volume create --size 8 $VOL_IMG_NAME --image $ID
        fi
    else
        echo "Creating empty 1 GB Cinder volume"
        if [ $CINDER_AZN -eq 1 ]; then
            openstack volume create --size 1 $VOL_NAME --availability-zone $AZ
        else
            openstack volume create --size 1 $VOL_NAME
        fi
    fi
    sleep 5
    echo "Listing Cinder Ceph Pool and Volume List"
    openstack volume list
    if [ $CINDER_AZN -eq 1 ]; then
        rceph $NUM rbd -p volumes ls -l
    else
        rceph 0 rbd -p volumes ls -l
    fi
fi

if [ $NOVA_CONTROL_LOGS -eq 1 ]; then
    oc get pods | grep nova | grep -v controller
    for POD in $(oc get pods | grep nova | grep -v controller | awk {'print $1'}); do
        echo $POD
        echo "~~~"
        oc logs $POD | grep ERROR | grep -v ERROR_FOR_DIVISION_BY_ZERO
        echo "~~~"
    done
fi

if [ $NOVA_COMPUTE_LOGS -eq 1 ]; then
    NODE="compute-0"
    # NODE="compute-$BEG"
    SSH_CMD="ssh $SSH_OPT $NODE"
    $SSH_CMD "hostname"
    $SSH_CMD "sudo grep ERROR /var/log/containers/nova/nova-compute.log"
    $SSH_CMD "date"
fi

if [ $PRINET -eq 1 ]; then
    openstack network create private --share
    openstack subnet create priv_sub --subnet-range 192.168.0.0/24 --network private
fi

if [ $VM_DEL -eq 1 ]; then
    echo "Ensuring there are no Nova VMs"
    openstack server list
    for IMG in $(SHOW_CMD=0 openstack server list -c ID -f value); do
        # had issue with new lines, so cleaning
        ID=$(echo $IMG | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
        openstack server delete $ID
    done
    openstack server list
fi

if [ $VM -eq 1 ]; then
    FLAV_ID=$(SHOW_CMD=0 openstack flavor show c1 -f value -c id 2> /dev/null)
    if [[ $? -gt 0 ]]; then
        openstack flavor create c1 --vcpus 1 --ram 256
        FLAV_ID=$(SHOW_CMD=0 openstack flavor show c1 -f value -c id 2> /dev/null)
    fi
    FLAV_ID=$(echo $FLAV_ID | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
    if [[ $? -eq 0 ]]; then
        echo "Attempting to create $VM_NAME"
        if [ $PET -eq 0 ]; then
            for IMG in $(SHOW_CMD=0 openstack image list -c ID -f value); do
                # this loop should only run once, also clean whitespace from the UUID
                IMG_ID=$(echo $IMG | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
            done
            IMG_SRC="--image $IMG_ID"
        fi
        if [ $PET -eq 1 ]; then
            echo "Looking for volume \"$VOL_IMG_NAME\""
            VOL=$(SHOW_CMD=0 openstack volume show $VOL_IMG_NAME -c id -f value 2> /dev/null)
            VOL_ID=$(echo $VOL | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
            # did we get a UUID?
            if [[ $VOL_ID =~ ^\{?[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}\}?$ ]]; then
                IMG_SRC="--volume $VOL_ID"
            else
                echo "Error: please create volume \"$VOL_IMG_NAME\" first."
                exit 1
            fi
        fi
        echo "Creating VM with $IMG_SRC"
        if [ $VM_AZN -eq 1 ]; then
            openstack server create --flavor c1 $IMG_SRC --nic net-id=private $VM_NAME --availability-zone $AZ
        else
            openstack server create --flavor c1 $IMG_SRC --nic net-id=private $VM_NAME
        fi
        NOVA_ID=$(SHOW_CMD=0 openstack server show $VM_NAME -f value -c id 2> /dev/null)
    else
        echo "$NOVA_ID"
    fi
    NOVA_ID=$(echo $NOVA_ID | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
    openstack server list
    if [[ $(SHOW_CMD=0 openstack server list -c Status -f value \
                | while IFS= read -r line; do echo -n "$line"; done \
                | tr -d '[:space:]') == "BUILD" ]]; then
        echo "Waiting one 30 seconds for building server to boot"
        sleep 30
    fi
    openstack server list
    if [ $VM_AZN -eq 1 ]; then
        rceph $NUM rbd -p vms ls -l
    else
        rceph 0 rbd -p vms ls -l
    fi
    if [ $PET -eq 1 ]; then
        openstack volume list
    fi
fi

if [ $CONSOLE -eq 1 ]; then
    openstack console log show $VM_NAME
fi

if [ $CEPH_REPORT -eq 1 ]; then
    rceph 0 ceph -s
    rceph $NUM ceph -s
    rceph 0 rbd -p images ls -l
    rceph $NUM rbd -p images ls -l
fi
