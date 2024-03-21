# DCN with openstack-k8s-operators

This repository hosts CRs and notes for a proof of concept of using
[openstack-k8s-operators](https://github.com/openstack-k8s-operators)
to deploy HCI
[Distributed Compute Nodes](https://www.redhat.com/en/blog/introduction-openstacks-distributed-compute-nodes).

## Assumptions

- The reader is already familiar with how to deploy the
[Development Preview](https://access.redhat.com/rhosp-18-dev-preview-3-release-notes)
using Hyperconverged Infrastructure with one Ceph cluster
providing RBD support for Nova, Glance and Cinder.

- All hardware is pre-provisioned. See [design example](design.md)
  for how many nodes and AZs are used in the example CRs.

## Steps

To implement the [design example](design.md) three AZs are deployed
sequentially and then AZ0 is updated. Each link below contains example
CRs and notes.

- [Deploy AZ0](az0)
- [Deploy AZ1](az1)
- [Deploy AZ2](az2)
- [Update AZ0](update)
