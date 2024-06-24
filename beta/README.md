# Beta

This beta sub-directory is a derivative work of the original CRs but with the following changes:

1. spine and leaf networking (see `routes` in control-plane.yaml and nncp.yaml)
2. dataplane CRs (e.g. dataplane-pre-ceph.yaml) were split for separate nodesets and deployments (e.g. nodeset-pre-ceph.yaml and deployment-pre-ceph.yaml)
3. updates for the new content from the [RHOSO 18.0 Beta](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift/18.0-beta/html-single/release_notes/index)

Apply these CRs as described in the original instructions:

- [Deploy AZ0](../az0)
- [Deploy AZ1](../az1)
- [Deploy AZ2](../az2)

However:

- Instead of running `oc apply -f` with
[dataplane-pre-ceph.yaml](../az0/dataplane-pre-ceph.yaml),
run it with
[nodeset-pre-ceph.yaml](az0/nodeset-pre-ceph.yaml)
and then with
[deployment-pre-ceph.yaml](az0/deployment-pre-ceph.yaml).

- Instead of running `oc apply -f` with
[post-ceph.yaml](../az0/post-ceph.yaml),
run it with
[nodeset-post-ceph.yaml](az0/nodeset-post-ceph.yaml)
and then with
[deployment-post-ceph.yaml](az0/deployment-post-ceph.yaml).
