#!/usr/bin/env bash

# Personal script for automting AZ1 deployment using:
# - https://github.com/openstack-k8s-operators/ci-framework
# - https://github.com/openstack-k8s-operators/architecture/tree/main/examples/va/hci
# 
# The above and how it is kustomized is still experimental, and not part
# of the product, though it can be used to solve the problem of environment
# creation and environment variable substitution for testing.

DATAPLANE=0
CEPH=0
POSTCEPH=0
DISCOVER=0

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
    python ~/dcn/extra/node_filter.py $SRC edpm-pre-ceph/values.yaml --beg 3 --end 5
    kustomize build edpm-pre-ceph > dataplane-pre-ceph-az1-temp.yaml
    # change the name to include az1 and exclude secrets
    python ~/dcn/extra/nodeset_name.py dataplane-pre-ceph-az1-temp.yaml dataplane-pre-ceph-az1.yaml --num 1
    oc create -f dataplane-pre-ceph-az1.yaml
    oc wait osdpd edpm-deployment-pre-ceph-az1 --for condition=Ready --timeout=1200s
    popd
fi

if [ $CEPH -eq 1 ]; then
    bash ~/dcn/extra/ceph.sh 103 ceph_az1.yaml
fi

if [ $POSTCEPH -eq 1 ]; then
    # The AZ1 ceph deployment will overwrite the AZ0 versions with AZ1 versions
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
    kustomize build > post-ceph-az1-temp.yaml

    # Modify kustomize output with python to suit DCN scenario for any azN > 0
    # For the control plane we want:
    #   - a new glance edge instance with two backends (az0 and azN)
    #   - the default glance to keep using it's current backends but add azN
    #     (this currently has limitation as only az0 and last azN are used)
    #   - a new cinder-volume instance with its own new backend
    #
    # For the data plane we want:
    #   - to deploy the same genereated post ceph config
    python ~/dcn/extra/post-ceph-azn.py post-ceph-az1-temp.yaml post-ceph-az1.yaml \
	   --num 1 \
	   --ceph-secret $CEPH_SECRET_FILE \
	   --control-plane-cr $CONTROL_PLANE_CR_FILE

    # Apply the single modified post-ceph-az1.yaml file
    # oc apply -f post-ceph-az1.yaml

    # echo -e "\noc get pods -n openstack -w\n"
    # oc wait osctlplane controlplane --for condition=Ready --timeout=600s

    # Wait for ansible to finish
    # echo -e "\noc get pods -w -l app=openstackansibleee\n"
    # oc wait osdpd edpm-deployment-post-ceph-az1 --for condition=Ready --timeout=1200s
    popd
fi

if [ $DISCOVER -eq 1 ]; then
    oc rsh nova-cell0-conductor-0 nova-manage cell_v2 discover_hosts --verbose
    oc rsh openstackclient openstack compute service list
    oc rsh openstackclient openstack network agent list
fi

popd
