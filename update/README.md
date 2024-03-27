# Update Control Plane to use Multiple Ceph Backends

At this stage all three AZs and Ceph clusters from
the [design example](../design.md) are deployed.

The [Control Plane CR](../az0/control-plane.yaml#L104)
will be updated with something like the follow for multiple
Glances with multiple backends.

```
kind: OpenStackControlPlane
spec:
  ...
  glance:
    template:
      serviceUser: glance
      databaseInstance: openstack
      databaseAccount: glance
      keystoneEndpoint: default
      glanceAPIs:
        default:
          preserveJobs: false
          replicas: 1
          type: split
          customServiceConfig: |
            [DEFAULT]
            [glance_store]
            stores=http,rbd
            os_region_name=regionOne
            default_backend = az0

            [az0]
            store_description = "az0 RBD backend"
            rbd_store_pool = images
            rbd_store_user = az0.openstack
            rbd_store_ceph_conf = /etc/ceph/az0.conf

            [az1]
            store_description = "az1 RBD backend"
            rbd_store_pool = images
            rbd_store_user = az1.openstack
            rbd_store_ceph_conf = /etc/ceph/az1.conf

            [az2]
            store_description = "az2 RBD backend"
            rbd_store_pool = images
            rbd_store_user = az2.openstack
            rbd_store_ceph_conf = /etc/ceph/az2.conf

        az1:
          preserveJobs: false
          replicas: 1
          type: edge
          customServiceConfig: |
            [DEFAULT]
            [glance_store]
            stores=http,rbd
            os_region_name=regionOne
            default_backend = az1

            [az0]
            store_description = "az0 RBD backend"
            rbd_store_pool = images
            rbd_store_user = az0.openstack
            rbd_store_ceph_conf = /etc/ceph/az0.conf

            [az1]
            store_description = "az1 RBD backend"
            rbd_store_pool = images
            rbd_store_user = az1.openstack
            rbd_store_ceph_conf = /etc/ceph/az1.conf
        az2:
          preserveJobs: false
          replicas: 1
          type: edge
          customServiceConfig: |
            [DEFAULT]
            [glance_store]
            stores=http,rbd
            os_region_name=regionOne
            default_backend = az2

            [az0]
            store_description = "az0 RBD backend"
            rbd_store_pool = images
            rbd_store_user = az0.openstack
            rbd_store_ceph_conf = /etc/ceph/az0.conf

            [az2]
            store_description = "az2 RBD backend"
            rbd_store_pool = images
            rbd_store_user = az2.openstack
            rbd_store_ceph_conf = /etc/ceph/az2.conf
```

There will be
[multiple Ceph keyrings and confs in one secret](https://github.com/openstack-k8s-operators/docs/blob/main/ceph.md#regarding-multiple-ceph-keyrings)
so that a single
[extraMounts](https://github.com/openstack-k8s-operators/docs/blob/main/ceph.md#access-the-ceph-secret-via-extramounts)
can be used to popluate `/etc/ceph`.
