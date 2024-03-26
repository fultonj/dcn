# Deploy AZ0

In this step we deploy the AZ0 subset of
the [design example](../design.md).

## Prerequisites

- Chapters 1, 2 and 3 of the Deployment document from
  [Development Preview](https://access.redhat.com/rhosp-18-dev-preview-3-release-notes)
  have been completed.

- `oc get pods -n openstack-operators` returns a list of running
  OpenStack operators

## Overview

This directory contains CRs which should be applied and verified in
the order which is documented here. Anyone should be able to take
these example CRs and modify them for their environment.

## CRs: networking and control plane

- [nncp.yaml](nncp.yaml)
- [control-plane.yaml](control-plane.yaml)

### Apply and Verify

```
oc apply -f nncp.yaml
oc wait nncp -l osp/nncm-config-type=standard --for jsonpath='{.status.conditions[0].reason}'=SuccessfullyConfigured --timeout=300s
```

```
oc apply -f control-plane.yaml
oc wait osctlplane controlplane --for condition=Ready --timeout=600s
```

## CRs: pre-ceph data plane

- [dataplane-pre-ceph.yaml](dataplane-pre-ceph.yaml)

### Apply and Verify

```
oc apply -f dataplane-pre-ceph.yaml
oc get pods -w -l app=openstackansibleee
oc wait osdpd edpm-deployment-pre-ceph --for condition=Ready --timeout=1200s
```

## Deploy Ceph for AZ0

In this step the `cephadm` tool should be used to deploy Ceph on
edpm-compute-0, edpm-compute-1 and edpm-compute-2.

After the Ceph cluster is deployed create pools for Nova, Cinder and
Glance, and then create an openstack keyring to access them. Export
the keyring and a ceph configuration file to a secret CR. Steps to
do this are documented
[upstream](https://github.com/openstack-k8s-operators/docs/blob/main/ceph.md)
and in the Deployment document from
[Development Preview](https://access.redhat.com/rhosp-18-dev-preview-3-release-notes).

## CRs: post-ceph control and data plane

- [post-ceph.yaml](post-ceph.yaml)

### Apply and Verify
```
oc apply -f post-ceph.yaml
```
Wait for post-Ceph control plane to be available after updating
```
oc wait osctlplane controlplane --for condition=Ready --timeout=600s
```
Wait for post-Ceph data plane deployment to finish
```
oc wait osdpd edpm-deployment-post-ceph --for condition=Ready --timeout=1200s
```

## Discover Nova computes in AZ0

Ask Nova to discover all compute hosts in AZ0.
```
oc rsh nova-cell0-conductor-0 nova-manage cell_v2 discover_hosts --verbose
```

AZ0 should now be deployed. Next [deploy AZ1](../az1).
