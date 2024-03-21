# Design Example

```
OpenShift
- AZ0 default openstack-k8s-operators pods
- AZ1 pods for cinder-volume-1/glance-1
- AZ2 pods for cinder-volume-2/glance-2

AZ0: (ceph0)
- edpm-compute-0
- edpm-compute-1
- edpm-compute-2

AZ1: (ceph1)
- edpm-compute-3
- edpm-compute-4
- edpm-compute-5

AZ2: (ceph2)
- edpm-compute-6
- edpm-compute-7
- edpm-compute-8
```

- Nine compute nodes are deployed with 3 nodes per AZ.
- Three three-node Ceph clusters are deployed per AZ.
- The deployment of AZ0 resources will look very similar to the HCI
  example from the
  [Development Preview](https://access.redhat.com/rhosp-18-dev-preview-3-release-notes).
- AZ1 and AZ2 are each managed as a separate
  [OpenStackDataPlaneNodeSet](https://openstack-k8s-operators.github.io/dataplane-operator/user/index.html#_dataplane_operator_crd_design_and_resources).
- AZ0 does not need to be physically in the same data center as OpenShift.
- The ceph cluster in AZ0 is the default storage backend for Glance,
  but the default Glance pod will be configured to access all Ceph
  clusters so that images may be copied between AZs.
- Compute nodes in AZ-N  will query the glance-N pod which will direct
  them to get them to use thier physically local Ceph cluster for all N.
- The data path remains local though the control path is stretched
  across AZs.
- The pattern can continue for more AZs
