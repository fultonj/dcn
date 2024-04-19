# Deploy AZ2

In this step we deploy the AZ2 subset of
the [design example](../design.md).

The CRs are provided for completeness though they are all derivative
works of the CRs from [AZ1](../az1).

- Apply [dataplane-pre-ceph-az2.yaml](dataplane-pre-ceph-az2.yaml)
- Deploy Ceph on edpm-compute-6, edpm-compute-7 and edpm-compute-8
- Apply [post-ceph-az2.yaml](post-ceph-az2.yaml)
- Discover Nova computes in AZ2
- Add AZ2 compute nodes to a host aggregate
- The same [testing pattern](../az1/testing.md) can be followed but
  substitute "az2" for "az1"

## Pattern for adding more AZs

Compare the post-ceph AZ1 to AZ2
```
diff -u az1/post-ceph-az1.yaml az2/post-ceph-az2.yaml
```
Aside from naming and host differences the multibackend storage
configuration from the `diff` command shows a pattern:

1. The AZ0 split Glance has 3 backends: AZ0 (default), AZ1, AZ2
2. The AZ1 edge Glance has 2 backends: AZ1 (defaullt), AZ0
3. The new AZ2 edge Glance has 2 backends: AZ2 (defaullt), AZ0
4. A new end point at glance-az2-internal.openstack.svc
   which uses loadBalancerIPs: 172.17.0.82
5. A new Cinder volume service was added for AZ2
6. New compute nodes in AZ2 use the new ceph cluster for AZ2

If another AZ was added, the next step of the pattern would be:

1. The AZ0 split Glance has 4 backends: AZ0 (default), AZ1, AZ2, AZ3
2. The AZ1 edge Glance has 2 backends: AZ1 (defaullt), AZ0
3. The AZ2 edge Glance has 2 backends: AZ2 (defaullt), AZ0
4. The new AZ3 edge Glance has 2 backends: AZ3 (defaullt), AZ0
5. A new end point at glance-az3-internal.openstack.svc
   which uses loadBalancerIPs: 172.17.0.83
6. A new Cinder volume service was added for AZ3
7. New compute nodes in AZ3 use the new ceph cluster for AZ3

With each AZ added we update the AZ0 glance to use the new Ceph
backend.
