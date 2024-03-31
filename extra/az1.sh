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

pushd ~/src/github.com/openstack-k8s-operators/architecture

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
    python ~/dcn/extra/nodeset_name.py dataplane-pre-ceph-az1-temp.yaml dataplane-pre-ceph-az1.yaml --num 1
    oc create -f dataplane-pre-ceph-az1.yaml
    oc wait osdpd edpm-deployment-pre-ceph-az1 --for condition=Ready --timeout=1200s
    popd
fi

if [ $CEPH -eq 1 ]; then
    bash ~/dcn/extra/ceph.sh 103 ceph_az1.yaml
fi

popd
