# Deploy AZ0

In this step we deploy the AZ0 subset of
the [design example](../design.md).

## Prerequisites

- Chapters 1, 2 and 3 of the Deployment document from
  [Development Preview](https://access.redhat.com/rhosp-18-dev-preview-3-release-notes)
  have been completed.

- `oc get pods -n openstack-operators` returns a list of running
  OpenStack operators

- `oc wait pod -n metallb-system -l component=speaker --for
  condition=Ready --timeout=300s` should indicate that all
  speaker pod conditions have been met.

- `oc wait deployments/nmstate-webhook -n openshift-nmstate --for
  condition=Available --timeout=300s` should return
  `deployment.apps/nmstate-webhook condition met`

## Overview

This directory contains CRs which should be applied and verified in
the order which is documented in here. You should be able to
take these example CRs and modify them for your environment. The
optional section of each stage describes the commands which were used
to generate the CRs.

For CR generation in this section it is possible to use the
[HCI VA](https://github.com/openstack-k8s-operators/architecture/tree/main/examples/va/hci)
with the
[ci-framework](https://github.com/openstack-k8s-operators/ci-framework).
For transparency and repeatability in my environment I have documented
the commands that I used to do this. The VA and how it is kustomized
is still experimental, and not part of a product, though it can be used
to solve the problem of environment variable substitution.

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

### Optional CR generation

```
pushd ~/src/github.com/openstack-k8s-operators/architecture/examples/va/hci/
cp ~/ci-framework-data/artifacts/ci_gen_kustomize_values/network-values/values.yaml control-plane/nncp/values.yaml
kustomize build control-plane/nncp > nncp.yaml
kustomize build control-plane > control-plane.yaml
popd
```

## CRs: pre-ceph data plan

- [dataplane-pre-ceph.yaml](dataplane-pre-ceph.yaml)

### Apply and Verify

```
oc apply -f dataplane-pre-ceph.yaml
oc get pods -w -l app=openstackansibleee
oc wait osdpd edpm-deployment-pre-ceph --for condition=Ready --timeout=1200s
```

### Optional CR generation

```
pushd ~/src/github.com/openstack-k8s-operators/architecture/examples/va/hci/
cp ~/ci-framework-data/artifacts/ci_gen_kustomize_values/edpm-values/values.yaml edpm-pre-ceph/values.yaml
kustomize build control-plane/nncp > nncp.yaml
kustomize build edpm-pre-ceph > dataplane-pre-ceph.yaml
popd
```
Ensure the `nodes` list only has has three computes.
