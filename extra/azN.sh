#!/usr/bin/env bash

# Personal script for automating AZn deployment using:
# - https://github.com/openstack-k8s-operators/ci-framework
# - https://github.com/openstack-k8s-operators/architecture/tree/main/examples/va/hci
#
# The above and how it is kustomized is still experimental, and not part
# of the product, though it can be used to solve the problem of environment
# creation and environment variable substitution for testing.

DATAPLANE=0
CEPH=0
DNSHACK=0
POSTCEPH=0
DISCOVER=0
AGGREGATE=0

# 1 for AZ1 xor 2 for AZ2
NUM=1

APPLY=1
BACKUP=/tmp/dcn/az${NUM}
mkdir -p $BACKUP

if [ $NUM -eq 1 ]; then
    BEG=3
    END=5
    CEPH_LAST_OCTET=103
    CEPH_OVERRIDE=ceph_az1.yaml
    EDPM_PRE_CR=edpm-deployment-pre-ceph-az1
    EDPM_POST_CR=edpm-deployment-post-ceph-az1
fi
if [ $NUM -eq 2 ]; then
    BEG=6
    END=8
    CEPH_LAST_OCTET=106
    CEPH_OVERRIDE=ceph_az2.yaml
    EDPM_PRE_CR=edpm-deployment-pre-ceph-az2
    EDPM_POST_CR=edpm-deployment-post-ceph-az2
fi

export PASS=$(cat ~/.kube/kubeadmin-password)
oc login -u kubeadmin -p $PASS https://api.ocp.openstack.lab:6443
if [[ $? -gt 0 ]]; then
    exit 1
fi

export ARCH=~/src/github.com/openstack-k8s-operators/architecture

# identify first ceph deployment secret file
export CEPH_SECRET_FILE=~/az0_ceph_secret.yaml
if [[ ! -e $CEPH_SECRET_FILE ]]; then
    echo "CEPH_SECRET_FILE $CEPH_SECRET_FILE is missing; copying new one"
    if [[ ! -e /tmp/k8s_ceph_secret.yml ]]; then
	echo "Secret from first ceph deployment is missing; unable to copy"
	exit 1
    else
	cp -v /tmp/k8s_ceph_secret.yml $CEPH_SECRET_FILE
    fi
fi

# identify first control plane CR
export CONTROL_PLANE_CR_FILE=~/control-plane-cr.yaml
if [[ ! -e $CONTROL_PLANE_CR_FILE ]]; then
    echo "CONTROL_PLANE_CR_FILE $CONTROL_PLANE_CR_FILE is missing; copying new one"
    if [[ ! -e $ARCH/examples/va/hci/dataplane-post-ceph.yaml ]]; then
	echo "Control Plane CR from first deployment is missing; unable to copy"
	exit 1
    else
	# copy it and ensure only kind OpenStackControlPlane is left
	# It is called dataplane-post-ceph.yaml, but post-ceph.yaml is a better name
	python ~/dcn/extra/control_plane_filter.py \
	       $ARCH/examples/va/hci/dataplane-post-ceph.yaml $CONTROL_PLANE_CR_FILE
	ls -l $CONTROL_PLANE_CR_FILE
    fi
fi


pushd $ARCH

if [ $DATAPLANE -eq 1 ]; then
    SRC=~/ci-framework-data/artifacts/ci_gen_kustomize_values/edpm-values/values.yaml
    if [[ ! -e $SRC ]]; then
        echo "$SRC is missing"
        exit 1
    fi
    echo -e "\noc get pods -w -l app=openstackansibleee\n"

    pushd examples/va/hci/
    python ~/dcn/extra/node_filter.py $SRC edpm-pre-ceph/values.yaml --beg $BEG --end $END
    kustomize build edpm-pre-ceph > dataplane-pre-ceph-azN-temp.yaml
    # change the name to include azN and exclude secrets
    python ~/dcn/extra/nodeset_name.py dataplane-pre-ceph-azN-temp.yaml dataplane-pre-ceph-azN.yaml --num $NUM

    cp -v dataplane-pre-ceph-azN.yaml $BACKUP/dataplane-pre-ceph-az${NUM}.yaml
    if [ $APPLY -eq 1 ]; then
        oc apply -f dataplane-pre-ceph-azN.yaml
        oc wait osdpd $EDPM_PRE_CR --for condition=Ready --timeout=1200s
    fi
    popd
fi

if [ $CEPH -eq 1 ]; then
    bash ~/dcn/extra/ceph.sh $CEPH_LAST_OCTET $CEPH_OVERRIDE
fi

if [ $DNSHACK -eq 1 ]; then
    # short term hack, EDPM ansible will set this correctly
    DNS=$(oc get svc -l service=dnsmasq -o json | jq -r '.items[0].status.loadBalancer.ingress[0].ip')
    echo "Add \"nameserver $DNS\" to /etc/resolv.conf (and remove wrong DNS server)"
    # ceph.sh puts this inventory in place
    INV=~/src/github.com/openstack-k8s-operators/ci-framework/inventory.yml
    ansible -b -i $INV computes -m lineinfile \
            -a "path=/etc/resolv.conf line=\"nameserver 192.168.111.1\" state=absent"
    ansible -b -i $INV computes -m lineinfile \
            -a "path=/etc/resolv.conf line=\"nameserver $DNS\" state=present"
    # Not necessary if DNS is fixed before POSTCEPH
    # echo "restart ovn and nova_compute containers"
    # ansible -b -i $INV computes -m shell \
    #         -a "podman restart nova_compute"
    # ansible -b -i $INV computes -m shell \
    #         -a "podman restart ovn_controller"
    # ansible -b -i $INV computes -m shell \
    #         -a "podman restart ovn_metadata_agent"
fi


if [ $POSTCEPH -eq 1 ]; then
    # The AZN ceph deployment will overwrite the AZ0 versions with AZN versions
    SRC1=/tmp/edpm_values_post_ceph.yaml
    SRC2=/tmp/edpm_service_values_post_ceph.yaml
    for SRC in $SRC1 $SRC2; do
        if [[ ! -e $SRC ]]; then
            echo "$SRC is missing"
            exit 1
        fi
    done
    pushd examples/va/hci/
    cp $SRC1 ~/src/github.com/openstack-k8s-operators/architecture/examples/va/hci/values.yaml
    cp $SRC2 ~/src/github.com/openstack-k8s-operators/architecture/examples/va/hci/service-values.yaml
    kustomize build > post-ceph-azN-temp.yaml

    # Modify kustomize output with python to suit DCN scenario for any azN > 0
    # with post-ceph-azn.py.
    #
    # For the control plane we want:
    #   - a new glance edge instance with two backends (az0 and azN)
    #   - the default glance to keep using it's current backends but add azN
    #     (this currently has limitation as only az0 and last azN are used)
    #   - a new cinder-volume instance with its own new backend
    #
    # For the data plane we want:
    #   - to deploy the same genereated post ceph config
    python ~/dcn/extra/post-ceph-azn.py post-ceph-azN-temp.yaml post-ceph-azN.yaml \
	   --num $NUM \
	   --ceph-secret $CEPH_SECRET_FILE \
	   --control-plane-cr $CONTROL_PLANE_CR_FILE

    cp -v post-ceph-azN.yaml $BACKUP/post-ceph-az${NUM}.yaml

    # Apply the single modified post-ceph-azN.yaml file
    if [ $APPLY -eq 1 ]; then
        oc apply -f post-ceph-azN.yaml

        echo -e "\noc get pods -n openstack -w\n"
        oc wait osctlplane controlplane --for condition=Ready --timeout=600s

        # Wait for ansible to finish
        echo -e "\noc get pods -w -l app=openstackansibleee\n"
        oc wait osdpd $EDPM_POST_CR --for condition=Ready --timeout=1200s
    fi
    popd
fi

if [ $DISCOVER -eq 1 ]; then
    oc rsh nova-cell0-conductor-0 nova-manage cell_v2 discover_hosts --verbose
    oc rsh openstackclient openstack compute service list
    oc rsh openstackclient openstack network agent list
fi

if [ $AGGREGATE -eq 1 ]; then
    AZ="az${NUM}"
    echo "# Adding computes $BEG through $END to $AZ"
    OS="oc rsh openstackclient openstack"
    $OS aggregate create $AZ
    $OS aggregate set --zone $AZ $AZ
    for I in $(seq $BEG $END); do
        $OS aggregate add host $AZ compute-${I}.ctlplane.example.com
    done
    $OS compute service list -c Host -c Zone
    $OS volume service list
fi

popd
