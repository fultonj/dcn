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

## Observe Pods and Services

After the default, AZ1 and AZ2 deployments there should be a Cinder
volume pod for every Ceph cluster.
```
$ oc get pods | grep cinder-volume
cinder-volume-az1-0                                               2/2     Running     0              47h
cinder-volume-az2-0                                               2/2     Running     0              46m
cinder-volume-ceph-0                                              2/2     Running     0              47h
$
```
Each pod provides a cinder volume service for a unique ceph cluster
per zone ("nova" is the name of the default zone).
```
$ openstack volume service list
+------------------+---------------------------+------+---------+-------+----------------------------+
| Binary           | Host                      | Zone | Status  | State | Updated At                 |
+------------------+---------------------------+------+---------+-------+----------------------------+
| cinder-scheduler | cinder-scheduler-0        | nova | enabled | up    | 2024-04-19T21:02:48.000000 |
| cinder-volume    | cinder-volume-ceph-0@ceph | nova | enabled | up    | 2024-04-19T21:02:54.000000 |
| cinder-volume    | cinder-volume-az1-0@ceph  | az1  | enabled | up    | 2024-04-19T21:02:56.000000 |
| cinder-volume    | cinder-volume-az2-0@ceph  | az2  | enabled | up    | 2024-04-19T21:02:52.000000 |
+------------------+---------------------------+------+---------+-------+----------------------------+
$
```

With replicas set to 3 for glance, we have the following Glance pods.
```
$ oc get pods | grep glance | grep api
glance-az1-edge-api-0                                             3/3     Running     0              47h
glance-az1-edge-api-1                                             3/3     Running     0              47h
glance-az1-edge-api-2                                             3/3     Running     0              47h
glance-az2-edge-api-0                                             3/3     Running     0              47m
glance-az2-edge-api-1                                             3/3     Running     0              47m
glance-az2-edge-api-2                                             3/3     Running     0              47m
glance-default-external-api-0                                     3/3     Running     0              47m
glance-default-external-api-1                                     3/3     Running     0              47m
glance-default-external-api-2                                     3/3     Running     0              47m
glance-default-internal-api-0                                     3/3     Running     0              47m
glance-default-internal-api-1                                     3/3     Running     0              47m
glance-default-internal-api-2                                     3/3     Running     0              47m
$
```

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

If another AZ N was added, the next step of the pattern would be:

1. The AZ0 split Glance has N backends: AZ0 (default), AZ1, AZ2, AZN
2. The AZ1 edge Glance has 2 backends: AZ1 (defaullt), AZ0
3. The AZ2 edge Glance has 2 backends: AZ2 (defaullt), AZ0
4. The new AZN edge Glance has 2 backends: AZN (defaullt), AZ0
5. A new end point at glance-azN-internal.openstack.svc
   which uses loadBalancerIPs: 172.17.0.(80+N)
6. A new Cinder volume service was added for AZN
7. New compute nodes in AZN use the new ceph cluster for AZN

With each AZ site added, the the AZ0 glance is updated to use the new Ceph backend.
