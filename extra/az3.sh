#!/usr/bin/env bash
# Deploy an ephemeral compute node in AZ3

OCP_AUTH=0
DATAPLANE=0
DISCOVER=0
AGGREGATE=0

APPLY=1
mkdir -p /tmp/dcn/az3

NUM=3
BACKUP=/tmp/dcn/az${NUM}
mkdir -p $BACKUP
BEG=9
END=9

for F in yq kustomize; do
    if [[ ! -e ~/bin/$F ]]; then
        echo "Aborting: $F is not in ~/bin/$F"
        exit 1
    fi
done

if [ $OCP_AUTH -eq 1 ]; then
    export PASS=$(cat ~/.kube/kubeadmin-password)
    oc login -u kubeadmin -p $PASS https://api.ocp.openstack.lab:6443
    if [[ $? -gt 0 ]]; then
        exit 1
    fi
    oc project openstack > /dev/null
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
    python ~/dcn/extra/node_filter.py $SRC edpm-pre-ceph/values.yaml --beg $BEG --end $END
    kustomize build edpm-pre-ceph > dataplane-azN-temp.yaml
    # change the name to include azN and exclude secrets
    python ~/dcn/extra/nodeset_name.py dataplane-azN-temp.yaml dataplane-azN.yaml --no-ceph --num $NUM

    cp -v dataplane-azN.yaml $BACKUP/dataplane-az${NUM}.yaml
    if [ $APPLY -eq 1 ]; then
        oc apply -f dataplane-azN.yaml
        oc wait osdpd edpm-deployment-az${NUM} --for condition=Ready --timeout=1200s
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
fi

popd
