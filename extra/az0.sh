#!/usr/bin/env bash

# Personal script for automting AZ0 deployment using:
# - https://github.com/openstack-k8s-operators/ci-framework
# - https://github.com/openstack-k8s-operators/architecture/tree/main/examples/va/hci
# 
# The above and how it is kustomized is still experimental, and not part
# of the product, though it can be used to solve the problem of environment
# creation and environment variable substitution for testing.

OPERATORS=0
METALLB=0
NMSTATE=0

CONTROLPLANE=0
DATAPLANE=0
CEPH=0
POSTCEPH=0
DISCOVER=0

APPLY=1
mkdir -p /tmp/dcn/az0

for F in yq kustomize; do
    if [[ ! -e ~/.local/bin/$F ]] && [[ ! -e ~/bin/$F ]]; then
        echo "Aborting: $F is not in ~/[.local/]bin/$F"
        exit 1
    fi
done
export PASS=$(cat ~/.kube/kubeadmin-password)
oc login -u kubeadmin -p $PASS https://api.ocp.openstack.lab:6443
if [[ $? -gt 0 ]]; then
    exit 1
fi

pushd ~/src/github.com/openstack-k8s-operators/architecture

if [ $OPERATORS -eq 1 ]; then
    echo "oc get pods -w -n openstack-operators"
    # kustomize build examples/common/olm/

    oc apply -k examples/common/olm/

    while ! (oc get pod --no-headers=true -l name=cert-manager-operator -n cert-manager-operator| grep "cert-manager-operator"); do sleep 10; done
    
    oc wait pod -n cert-manager-operator --for condition=Ready -l name=cert-manager-operator --timeout=300s

    while ! (oc get pod --no-headers=true -l app=cainjector -n cert-manager | grep "cert-manager-cainjector"); do sleep 10; done
    oc wait pod -n cert-manager -l app=cainjector --for condition=Ready --timeout=300s

    while ! (oc get pod --no-headers=true -l app=webhook -n cert-manager | grep "cert-manager-webhook"); do sleep 10; done
    oc wait pod -n cert-manager -l app=webhook --for condition=Ready --timeout=300s

    while ! (oc get pod --no-headers=true -l app=cert-manager -n cert-manager | grep "cert-manager"); do sleep 10; done
    oc wait pod -n cert-manager -l app=cert-manager --for condition=Ready --timeout=300s

    timeout 300 bash -c "while ! (oc get pod --no-headers=true -l control-plane=controller-manager -n metallb-system | grep metallb-operator-controller); do sleep 10; done"
    
    oc wait pod -n metallb-system --for condition=Ready -l control-plane=controller-manager --timeout=300s

    timeout 300 bash -c "while ! (oc get pod --no-headers=true -l component=webhook-server -n metallb-system | grep metallb-operator-webhook); do sleep 10; done"

    oc wait pod -n metallb-system --for condition=Ready -l component=webhook-server --timeout=300s

    timeout 300 bash -c "while ! (oc get deployments/nmstate-operator -n openshift-nmstate); do sleep 10; done"
    oc wait deployments/nmstate-operator -n openshift-nmstate --for condition=Available --timeout=300s
    
fi

if [ $METALLB -eq 1 ]; then
    oc apply -k examples/common/metallb/
    timeout 300 bash -c "while ! (oc get pod --no-headers=true -l component=speaker -n metallb-system | grep speaker); do sleep 10; done"
    oc wait pod -n metallb-system -l component=speaker --for condition=Ready --timeout=300s
fi

if [ $NMSTATE -eq 1 ]; then
    oc apply -k examples/common/nmstate/

    timeout 300 bash -c "while ! (oc get pod --no-headers=true -l component=kubernetes-nmstate-handler -n openshift-nmstate| grep nmstate-handler); do sleep 10; done"
    oc wait pod -n openshift-nmstate -l component=kubernetes-nmstate-handler --for condition=Ready --timeout=300s
    timeout 300 bash -c "while ! (oc get deployments/nmstate-webhook -n openshift-nmstate); do sleep 10; done"
    oc wait deployments/nmstate-webhook -n openshift-nmstate --for condition=Available --timeout=300s

fi

oc project openstack > /dev/null

if [ $CONTROLPLANE -eq 1 ]; then    
    SRC=~/ci-framework-data/artifacts/ci_gen_kustomize_values/network-values/values.yaml
    if [[ ! -e $SRC ]]; then
        echo "$SRC is missing"
        exit 1
    fi
    echo -e "\noc get pods -n openstack\n"
    
    pushd examples/va/hci/
    cp $SRC control-plane/nncp/values.yaml
    kustomize build control-plane/nncp > nncp.yaml
    kustomize build control-plane > control-plane.yaml

    cp -v control-plane.yaml /tmp/dcn/az0
    if [ $APPLY -eq 1 ]; then
        oc apply -f nncp.yaml
        oc wait nncp -l osp/nncm-config-type=standard --for jsonpath='{.status.conditions[0].reason}'=SuccessfullyConfigured --timeout=300s

        sleep 5
        oc apply -f control-plane.yaml
        sleep 5
        oc wait osctlplane controlplane --for condition=Ready --timeout=600s
    fi

    popd
fi

if [ $DATAPLANE -eq 1 ]; then
    SRC=~/ci-framework-data/artifacts/ci_gen_kustomize_values/edpm-nodeset-values/values.yaml
    if [[ ! -e $SRC ]]; then
        echo "$SRC is missing"
        exit 1
    fi
    echo -e "\noc get pods -w -l app=openstackansibleee\n"

    pushd examples/va/hci/
    python ~/dcn/extra/node_filter.py $SRC edpm-pre-ceph/nodeset/values.yaml --beg 0 --end 2
    kustomize build edpm-pre-ceph/nodeset > nodeset-pre-ceph.yaml
    cp -v nodeset-pre-ceph.yaml /tmp/dcn/az0
    if [ $APPLY -eq 1 ]; then
        oc apply -f nodeset-pre-ceph.yaml
        oc wait osdpns openstack-edpm --for condition=SetupReady --timeout=600s
    fi

    SRC=~/ci-framework-data/artifacts/ci_gen_kustomize_values/edpm-deployment-values/values.yaml
    if [[ ! -e $SRC ]]; then
        echo "$SRC is missing"
        exit 1
    fi
    
    cp $SRC edpm-pre-ceph/deployment/
    kustomize build edpm-pre-ceph/deployment > deployment-pre-ceph.yaml
    cp -v deployment-pre-ceph.yaml /tmp/dcn/az0
    if [ $APPLY -eq 1 ]; then
        oc apply -f deployment-pre-ceph.yaml
        oc wait osdpns openstack-edpm --for condition=Ready --timeout=1500s
    fi
    popd
fi

if [ $CEPH -eq 1 ]; then
    bash ~/dcn/extra/ceph.sh 100 ceph_az0.yaml
fi

if [ $POSTCEPH -eq 1 ]; then
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
    # This effectively copies $SRC2 but also disables manila
    yq '.data.manila.enabled = false' $SRC2 > ~/src/github.com/openstack-k8s-operators/architecture/examples/va/hci/service-values.yaml

    kustomize build > nodeset-post-ceph.yaml
    kustomize build deployment > deployment-post-ceph.yaml

    NODES=$(grep edpm-compute nodeset-post-ceph.yaml | awk {'print $1'} | sort | uniq | wc -l)
    if [[ ! $NODES -eq 3 ]]; then
        echo "Aborting. You only want to deploy 3 nodes, not $NODES"
        grep edpm-compute nodeset-post-ceph.yaml | awk {'print $1'} | sort | uniq
        echo "$PWD/nodeset-post-ceph.yaml"
        exit 1
    fi

    cp -v nodeset-post-ceph.yaml /tmp/dcn/az0
    cp -v deployment-post-ceph.yaml /tmp/dcn/az0
    if [ $APPLY -eq 1 ]; then
        oc apply -f nodeset-post-ceph.yaml

        oc wait osdpns openstack-edpm --for condition=SetupReady --timeout=600s

        oc apply -f deployment-post-ceph.yaml

        echo -e "\noc get pods -n openstack -w\n"
        echo -e "\noc get pods -w -l app=openstackansibleee\n"

        oc wait osctlplane controlplane --for condition=Ready --timeout=600s
        oc wait osdpd edpm-deployment-post-ceph --for condition=Ready --timeout=40m
    fi
    popd
fi

if [ $DISCOVER -eq 1 ]; then
    oc rsh nova-cell0-conductor-0 nova-manage cell_v2 discover_hosts --verbose
    oc rsh openstackclient openstack compute service list
    oc rsh openstackclient openstack network agent list
fi

popd
