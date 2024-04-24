# Deploy AZ1

In this step we deploy the AZ1 subset of
the [design example](../design.md).

## CRs: pre-ceph data plane

- [dataplane-pre-ceph-az1.yaml](dataplane-pre-ceph-az1.yaml)

### Apply and Verify

```
oc apply -f dataplane-pre-ceph-az1.yaml
oc get pods -w -l app=openstackansibleee
oc wait osdpd edpm-deployment-pre-ceph-az1 --for condition=Ready --timeout=1200s
```

## Deploy Ceph for AZ1

In this step the `cephadm` tool should be used to deploy Ceph on
edpm-compute-3, edpm-compute-4 and edpm-compute-5.

After the Ceph cluster is deployed create pools for Nova, Cinder and
Glance, and then create an openstack keyring to access them. Add the
keyring and conf file to the existing Ceph Secret as described in
[multiple Ceph keyrings and confs in one secret](https://github.com/openstack-k8s-operators/docs/blob/main/ceph.md#regarding-multiple-ceph-keyrings)
so that a single
[extraMounts](https://github.com/openstack-k8s-operators/docs/blob/main/ceph.md#access-the-ceph-secret-via-extramounts)
can be used to popluate `/etc/ceph` for all control plane pods
so they can access multiple Ceph clusters.

An example of a multi ceph cluster `ceph-conf-files` ConfigMap secret
is the next section.

## CRs: post-ceph control and data plane

- [post-ceph-az1.yaml](post-ceph-az1.yaml)

### TLS-e not enabled for Glance

TLS-e is not enabled for Glance in this example. More testing
is being done so that we can have an exmple like this with TLS-e in
the future.

### Multibackend Configuration

Note the following about the CRs in
[post-ceph-az1.yaml](post-ceph-az1.yaml).

The `ceph-conf-files` ConfigMap in
[post-ceph-az1.yaml](post-ceph-az1.yaml) has a keyring and
configuration file for two Ceph clusters (`ceph` and `az1`).

The `glance` section of the `OpenStackControlPlane` kind inside
of [post-ceph-az1.yaml](post-ceph-az1.yaml) is configured with two
`glanceAPIs`:

1. `default` of type `split` which has two ceph backends `az0` and
   `az1` where `az0` is the default backend. The `split` type
   deployment hosts an endpoint at the name
   `glance-default-internal.openstack.svc`, which will resolve to the
   `loadBalancerIP` of `172.17.0.80`; just like a non-DCN deployment.

2. `az1` of type `edge` which has two ceph backends `az0` and `az1`
   where `az1` is the default backend. The edge type will result in an
   additional API endpoint being created which can be accessed at
   `http://glance-az1-internal.openstack.svc:9292`. This endpoint
   uses the `metallb.universe.tf/loadBalancerIPs:` of
   `172.17.0.81` (which differs from the other `loadBalancerIPs`.

The `cinder` section of the `OpenStackControlPlane` kind inside
of [post-ceph-az1.yaml](post-ceph-az1.yaml) is configured with two
`cinderVolumes`:

1. `ceph` which is configured to use the default ceph backend hosted
   on the first set of edpm compute nodes (compute-{0,1,2}).

2. `az1` with `backend_availability_zone` set to `az1` and its
   `glance_api_servers` set to
   `http://glance-az1-internal.openstack.svc:9292`.
   It is also configured to use `az1` ceph backend hosted on the
   second set of edpm compute nodes (compute-{3,4,5}). It also has
   `cross_az_attach` set to `false`.

The `ceph-nova-az1` ConfigMap has a `03-ceph-nova.conf` file with
configuration for libvirt to use the `az1` ceph cluster and for
glance to use the endpoin hosted at
`http://glance-az1-internal.openstack.svc:9292`
Its cinder section also has `cross_az_attach` set to `false`.

### Apply and Verify
```
oc apply -f post-ceph-az1.yaml
```
Wait for post-Ceph control plane to be available after updating
```
oc wait osctlplane controlplane --for condition=Ready --timeout=600s
```
Wait for post-Ceph AZ1 data plane deployment to finish
```
oc wait osdpd edpm-deployment-post-ceph-az1 --for condition=Ready --timeout=1200s
```

## Discover Nova computes in AZ1

Ask Nova to discover all compute hosts in AZ1.
```
oc rsh nova-cell0-conductor-0 nova-manage cell_v2 discover_hosts --verbose
```

## Add AZ1 compute nodes to a host aggregate

```
export AZ=az1
export OS="oc rsh openstackclient openstack"
$OS aggregate create $AZ
$OS aggregate set --zone $AZ $AZ
for I in $(seq 3 5); do
    $OS aggregate add host $AZ compute-${I}.ctlplane.example.com
done
$OS compute service list -c Host -c Zone
```

The basic DCN storage use case can now be tested with the default AZ
and AZ1. Follow the examples in [the testing document](testing.md).
After that, proceed to [deploy AZ2](../az2).
