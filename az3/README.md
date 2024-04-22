# Deploy AZ3

In this step we deploy the AZ3 subset of
the [design example](../design.md).

AZ3 has a single compute (edpm-compute-9) which only runs ephemeral
workloads so it does not need a local Ceph cluster.

## CRs: data plane

- [dataplane-az3.yaml](dataplane-az3.yaml)

### Apply and Verify
```
oc apply -f dataplane-az3.yaml
```
Wait for data plane deployment to finish
```
oc wait osdpd edpm-deployment-az3 --for condition=Ready --timeout=1200s
```

## Discover Nova computes in AZ3

Ask Nova to discover all compute hosts in AZ1.
```
oc rsh nova-cell0-conductor-0 nova-manage cell_v2 discover_hosts --verbose
```

## Add AZ3 compute nodes to a host aggregate

```
export AZ=az3
export OS="oc rsh openstackclient openstack"
$OS aggregate create $AZ
$OS aggregate set --zone $AZ $AZ
$OS aggregate add host $AZ compute-9.ctlplane.example.com
$OS compute service list -c Host -c Zone
```

You should now be able to schedule ephemeral workloads in AZ3.
