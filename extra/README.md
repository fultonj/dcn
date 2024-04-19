# Extra Files for DCN

This directory is only relevant if you are using
[ci-framework](https://github.com/openstack-k8s-operators/ci-framework)
and a variation of
[VA1](https://github.com/openstack-k8s-operators/architecture/tree/main/examples/va/hci)
to deploy this architecture for testing on a single hypervisor.

## Prepare Environment

Use ci-framework as if you were deploying VA1 but add the following
overrides:

```
cifmw_libvirt_manager_compute_amount: 9
cifmw_kustomize_deploy_generate_crs_only: true
cifmw_deploy_architecture_stopper: post_apply_stage_3
```
The above do the following:

- deploy 10 VMs which will be EDPM nodes (see [design](../design.md))
- generates the `values.yaml` files with kustomize but doens't apply them
- fails the deployment early at stage 3

On my hardware after 76 minutes I saw the following as desired:
```
-0400 (0:00:00.040)       0:01:44.981 ******** ", 
"fatal: [localhost]: FAILED! => {\"changed\": false, 
\"msg\": \"Failing on demand post_apply_stage_3\"}
```

The subsequent steps should be run on as zuul@controller-0.

## Confirm values files were generated

Connect to controller-0 as zuul and use `find . -name values.yaml`
to confirm that the following files were generated with values from
the environment.

```
./ci-framework-data/artifacts/ci_gen_kustomize_values/olm-values/values.yaml
./ci-framework-data/artifacts/ci_gen_kustomize_values/network-values/values.yaml
./ci-framework-data/artifacts/ci_gen_kustomize_values/edpm-values/values.yaml
./ci-framework-data/artifacts/ci_gen_kustomize_values/service-values/values.yaml
./ci-framework-data/artifacts/ci_gen_kustomize_values/edpm-values-post-ceph/values.yaml
```
If the above were not generated they can still be generated with the
following command.
```
./deploy-architecture.sh --tags infra,edpm -e \
    cifmw_kustomize_deploy_generate_crs_only=true -e \
    cifmw_deploy_architecture_stopper=post_apply_stage_3
```
Clone this "dcn" repository to `/home/zuul/dcn` as zuul@controller-0.

## Deploy

As zuul@controller-0 use `az0.sh` to finish the VA1 deployment by
enabling parts of the script in sequence. The script will call other
scripts to modify the CRs. This is necessary so that only three EDPM
nodes are deployed for the default AZ (see [design](../design.md)).

Use `azN.sh` to deploy AZ1 (see [design](../design.md)) and AZ2 (set `NUM=2`).

Use `test.sh` to test that the default AZ (aka AZ0) and AZ1 or AZ2
work as expected.

The other python and shell scripts and configuration files in the
extra directory are called by the above shell scripts. These scripts
either deploy Ceph or modify CRs so that multiple storage backends
are configured.
