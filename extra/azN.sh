#!/usr/bin/env bash

# Personal script for automating AZn deployment using:
# - https://github.com/openstack-k8s-operators/ci-framework
# - https://github.com/openstack-k8s-operators/architecture/tree/main/examples/va/hci
#
# The above and how it is kustomized is still experimental, and not part
# of the product, though it can be used to solve the problem of environment
# creation and environment variable substitution for testing.

SETUP_PREV=0
DATAPLANE=0
CEPH=0
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
    EDPM_PRE_CR=openstack-edpm-az1
    EDPM_POST_CR=edpm-deployment-post-ceph-az1
fi
if [ $NUM -eq 2 ]; then
    BEG=6
    END=8
    CEPH_LAST_OCTET=106
    CEPH_OVERRIDE=ceph_az2.yaml
    EDPM_PRE_CR=openstack-edpm-az2
    EDPM_POST_CR=edpm-deployment-post-ceph-az2
fi

export PASS=$(cat ~/.kube/kubeadmin-password)
oc login -u kubeadmin -p $PASS https://api.ocp.openstack.lab:6443
if [[ $? -gt 0 ]]; then
    exit 1
fi

export ARCH=~/src/github.com/openstack-k8s-operators/architecture

if [ $SETUP_PREV -eq 1 ]; then
    # Identify current ceph secret file (before deploying another ceph cluster)
    export CEPH_SECRET_FILE=~/ceph_secret.yaml
    oc get Secret ceph-conf-files -o yaml \
        | yq 'del(.metadata.annotations, .metadata.creationTimestamp, .metadata.resourceVersion, .metadata.uid)' \
             > $CEPH_SECRET_FILE

    # Identify current control plane CR (before deploying another control plane)
    export CONTROL_PLANE_CR_FILE=~/control-plane-cr.yaml
    # Look at the previous N
    POST_CEPH_SRC=$ARCH/examples/va/hci/nodeset-post-ceph-azN.yaml
    if [[ ! -e $POST_CEPH_SRC ]]; then
        # if azN.sh has not been run before to create this file
        # then use the one from az0.sh
        # It is called dataplane-post-ceph.yaml, but post-ceph.yaml is a better name
        POST_CEPH_SRC=$ARCH/examples/va/hci/nodeset-post-ceph.yaml
        if [[ ! -e $POST_CEPH_SRC ]]; then
	    echo "Control Plane CR from first deployment is missing; unable to copy"
	    exit 1
        fi
    fi
    # Copy it and ensure only kind OpenStackControlPlane is left
    python ~/dcn/extra/control_plane_filter.py $POST_CEPH_SRC $CONTROL_PLANE_CR_FILE
    ls -l $CONTROL_PLANE_CR_FILE
fi

for F in $CEPH_SECRET_FILE $CONTROL_PLANE_CR_FILE; do
    if [[ ! -e $F ]]; then
        echo "Aborting: $F is missing (run again with SETUP_PREV=1?)"
    fi
done


pushd $ARCH


if [ $DATAPLANE -eq 1 ]; then
    SRC=~/ci-framework-data/artifacts/ci_gen_kustomize_values/edpm-nodeset-values/values.yaml
    if [[ ! -e $SRC ]]; then
        echo "$SRC is missing"
        exit 1
    fi
    echo -e "\noc get pods -w -l app=openstackansibleee\n"

    pushd examples/va/hci/
    python ~/dcn/extra/node_filter.py $SRC edpm-pre-ceph/nodeset/values.yaml --beg $BEG --end $END
    kustomize build edpm-pre-ceph/nodeset > nodeset-pre-ceph-azN-temp.yaml
    # change the name to include azN and exclude secrets
    python ~/dcn/extra/nodeset_name.py nodeset-pre-ceph-azN-temp.yaml nodeset-pre-ceph-azN.yaml --num $NUM

    cp -v nodeset-pre-ceph-azN.yaml $BACKUP/nodeset-pre-ceph-az${NUM}.yaml
    if [ $APPLY -eq 1 ]; then
        oc apply -f nodeset-pre-ceph-azN.yaml
	oc wait osdpns $EDPM_PRE_CR --for condition=SetupReady --timeout=600s
    fi

    SRC=~/ci-framework-data/artifacts/ci_gen_kustomize_values/edpm-deployment-values/values.yaml
    if [[ ! -e $SRC ]]; then
        echo "$SRC is missing"
        exit 1
    fi

    cp $SRC edpm-pre-ceph/deployment/
    kustomize build edpm-pre-ceph/deployment > deployment-pre-ceph-azN-temp.yaml
    python ~/dcn/extra/nodeset_name.py deployment-pre-ceph-azN-temp.yaml deployment-pre-ceph-azN.yaml --num $NUM
    cp -v deployment-pre-ceph-azN.yaml $BACKUP/deployment-pre-ceph-az${NUM}.yaml
    if [ $APPLY -eq 1 ]; then
        oc apply -f deployment-pre-ceph-azN.yaml
        oc wait osdpns $EDPM_PRE_CR --for condition=Ready --timeout=1500s
    fi
    
    popd
fi

if [ $CEPH -eq 1 ]; then
    bash ~/dcn/extra/ceph.sh $CEPH_LAST_OCTET $CEPH_OVERRIDE
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
    # This effectively copies $SRC2 but also disables manila
    yq '.data.manila.enabled = false' $SRC2 > ~/src/github.com/openstack-k8s-operators/architecture/examples/va/hci/service-values.yaml
    kustomize build > nodeset-post-ceph-azN-temp.yaml
    kustomize build deployment > deployment-post-ceph-azN-temp.yaml

    # change the name to include azN and exclude secrets
    python ~/dcn/extra/nodeset_name.py deployment-post-ceph-azN-temp.yaml deployment-post-ceph-azN.yaml --num $NUM

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
    python ~/dcn/extra/post-ceph-azn.py nodeset-post-ceph-azN-temp.yaml nodeset-post-ceph-azN.yaml \
	   --num $NUM \
	   --ceph-secret $CEPH_SECRET_FILE \
	   --control-plane-cr $CONTROL_PLANE_CR_FILE

    cp -v nodeset-post-ceph-azN.yaml $BACKUP/nodeset-post-ceph-az${NUM}.yaml
    cp -v deployment-post-ceph-azN.yaml $BACKUP/deployment-post-ceph-az${NUM}.yaml

    # Apply the single modified post-ceph-azN.yaml file
    if [ $APPLY -eq 1 ]; then
	oc apply -f nodeset-post-ceph-azN.yaml

        oc wait osdpns $EDPM_PRE_CR --for condition=SetupReady --timeout=600s

        oc apply -f deployment-post-ceph-azN.yaml

        echo -e "\noc get pods -n openstack -w\n"
        oc wait osctlplane controlplane --for condition=Ready --timeout=600s

        # Wait for ansible to finish
        echo -e "\noc get pods -w -l app=openstackansibleee\n"
        oc wait osdpd $EDPM_POST_CR --for condition=Ready --timeout=40m
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
