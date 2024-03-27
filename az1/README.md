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
