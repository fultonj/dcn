#!/usr/bin/env bash
# Import an image into the default and AZn locations
# Boot an instance and create a volume in the default location
# Boot an instance and create a volume in the AZn location
# -------------------------------------------------------
# VARS
OVERVIEW=0
GLANCE_SANITY=0
GLANCE_DEL=1
MULTI_GLANCE=1
NOVA_DEFAULT=0
NOVA_AZN=0
CINDER_AZN=0
PET_AZN=0
CEPH_REPORT=0

# Set "n"
# 1 for AZ1 xor 2 for AZ2
NUM=1
AZ="az${NUM}"

if [ $NUM -eq 1 ]; then
    BEG=3
    END=5
fi
if [ $NUM -eq 2 ]; then
    BEG=6
    END=8
fi

CIR=cirros-0.5.2-x86_64-disk.img
CIR_URL=http://download.cirros-cloud.net/0.5.2/$CIR
IMG_NAME=cirros
VOL_NAME=vol-$(date +%s)
VM_NAME=vm-$(date +%s)
VOL_IMG_NAME="${VOL_NAME}-${IMG_NAME}"

SSH_OPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# -------------------------------------------------------
# FUNCTIONS

openstack() {
    # Run openstack command inside openstackclient pod
    oc rsh -t --shell='/bin/sh' openstackclient openstack $@
}

glance() {
    # Run glance command inside openstackclient pod
    # From opentsackclient pod's `.config/openstack/clouds.yaml`
    END=https://keystone-public-openstack.apps.ocp.openstack.lab
    oc rsh -t --shell='/bin/sh' openstackclient glance --os-auth-url $END --os-project-name admin --os-username admin --os-password 12345678 --os-user-domain-name default --os-project-domain-name default $@
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

if [ $OVERVIEW -eq 1 ]; then
    openstack endpoint list
    openstack network agent list
    openstack compute service list
    openstack volume service list
    openstack aggregate list
    openstack aggregate show $AZ
fi

if [ $GLANCE_SANITY -eq 1 ]; then
    GLANCE_ENDPOINT=$(openstack endpoint list -f value -c "Service Name" -c "Interface" -c "URL" | grep glance | grep public | awk {'print $3'})
    if [[ $(curl -s $GLANCE_ENDPOINT | grep Unavailable | wc -l) -gt 0 ]]; then
        echo "curl $GLANCE_ENDPOINT returns unavailable (glance broken?)"
        curl -s $GLANCE_ENDPOINT
        exit 1
    fi
    glance image-list
    if [[ $? -gt 0 ]]; then
        echo "Aborting. Not even 'glance image-list' works."
        exit 1
    fi
fi

if [ $GLANCE_DEL -eq 1 ]; then
    echo "Ensuring there are no Glance images"
    glance image-list
    for IMG in $(openstack image list -c ID -f value); do
        # had issue with new lines, so cleaning
        ID=$(echo $IMG | while IFS= read -r line; do echo -n "$line"; done | tr -d '[:space:]')
        openstack image delete $ID
    done
    glance image-list
fi

if [ $MULTI_GLANCE -eq 1 ]; then
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
    for IMG in $(openstack image list -c ID -f value); do
        # this loop should only run once
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

if [ $CEPH_REPORT -eq 1 ]; then
    rceph 0 ceph -s
    rceph $NUM ceph -s
    rceph 0 rbd -p images ls -l
    rceph $NUM rbd -p images ls -l
fi
