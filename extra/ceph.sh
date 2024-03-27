#!/usr/bin/env bash

if [ "$#" -lt 2 ]; then
    echo "USAGE: $0 <NUM> <CEPH-OVERRIDE-FILE>"
    echo "<NUM> should be 100 for az0, 103 for az1, or 106 for az2"
    echo "      Assume compute-0's IP ends in 100, compute-3's IP ends in 103, ..."
    echo "<CEPH-OVERRIDE-FILE> should match ceph_az*.yaml"
    exit 1
fi

START=$1

pushd ~/src/github.com/openstack-k8s-operators/ci-framework/
export N=2
echo -e "localhost ansible_connection=local\n[computes]" > inventory.yml
for I in $(seq $START $((N+$START))); do
    echo 192.168.122.${I} >> inventory.yml
done
export ANSIBLE_REMOTE_USER=zuul
export ANSIBLE_SSH_PRIVATE_KEY=~/.ssh/id_cifw
export ANSIBLE_HOST_KEY_CHECKING=False

ansible -i inventory.yml -m ping computes
if [ $? -gt 0 ]; then
    echo "inventory problem"
    exit 1
fi
ln -fs ~/dcn/extra/$2
ln -fs ~/hci.yaml
ANSIBLE_GATHERING=implicit ansible-playbook playbooks/ceph.yml -e @hci.yaml -e @ceph.yaml -e @$2
popd
