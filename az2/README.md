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

Note that size of the Internal API network pool will need to be large
enough to accommodate the number of DCN sites. In the example below
only 10 IPs are available (from .80 to .90) so only 10 DCN sites can
have load balancer IPs (for each internal Glance endpiont), until the
size of the IP address pool is increased.
```
$ oc get ipaddresspool -n metallb-system
NAME          AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
ctlplane      true          false             ["192.168.122.80-192.168.122.90"]
internalapi   true          false             ["172.17.0.80-172.17.0.90"]
storage       true          false             ["172.18.0.80-172.18.0.90"]
tenant        true          false             ["172.19.0.80-172.19.0.90"]
$
```

With each AZ site added, the the AZ0 glance is updated to use the new Ceph backend.

### Observe services, routes and PVCs

```
$ oc get svc
NAME                           TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                                          AGE
cinder-internal                LoadBalancer   172.30.19.249    172.17.0.80      8776:30632/TCP                                   8d
cinder-public                  ClusterIP      172.30.123.106   <none>           8776/TCP                                         8d
dnsmasq-dns                    LoadBalancer   172.30.27.180    192.168.122.80   53:30103/UDP                                     8d
glance-az1-edge-api            ClusterIP      None             <none>           9292/TCP                                         8d
glance-az1-internal            LoadBalancer   172.30.64.50     172.17.0.81      9292:31088/TCP                                   8d
glance-az2-edge-api            ClusterIP      None             <none>           9292/TCP                                         6d18h
glance-az2-internal            LoadBalancer   172.30.95.221    172.17.0.82      9292:31250/TCP                                   6d18h
glance-default-external-api    ClusterIP      None             <none>           9292/TCP                                         8d
glance-default-internal        LoadBalancer   172.30.129.123   172.17.0.80      9292:31842/TCP                                   8d
glance-default-internal-api    ClusterIP      None             <none>           9292/TCP                                         8d
glance-default-public          ClusterIP      172.30.108.250   <none>           9292/TCP                                         8d
horizon                        ClusterIP      172.30.69.7      <none>           443/TCP                                          8d
keystone-internal              LoadBalancer   172.30.183.116   172.17.0.80      5000:32536/TCP                                   8d
keystone-public                ClusterIP      172.30.162.143   <none>           5000/TCP                                         8d
memcached                      ClusterIP      None             <none>           11211/TCP                                        8d
neutron-internal               LoadBalancer   172.30.135.68    172.17.0.80      9696:31994/TCP                                   8d
neutron-public                 ClusterIP      172.30.109.114   <none>           9696/TCP                                         8d
nova-internal                  LoadBalancer   172.30.253.225   172.17.0.80      8774:32656/TCP                                   8d
nova-metadata-internal         LoadBalancer   172.30.205.242   172.17.0.80      8775:30205/TCP                                   8d
nova-novncproxy-cell1-public   ClusterIP      172.30.167.80    <none>           6080/TCP                                         8d
nova-public                    ClusterIP      172.30.101.191   <none>           8774/TCP                                         8d
openstack                      ClusterIP      172.30.163.111   <none>           3306/TCP                                         8d
openstack-cell1                ClusterIP      172.30.87.114    <none>           3306/TCP                                         8d
openstack-cell1-galera         ClusterIP      None             <none>           3306/TCP                                         8d
openstack-galera               ClusterIP      None             <none>           3306/TCP                                         8d
ovsdbserver-nb                 ClusterIP      None             <none>           6643/TCP                                         8d
ovsdbserver-nb-0               ClusterIP      172.30.36.86     <none>           6641/TCP,6643/TCP                                8d
ovsdbserver-sb                 ClusterIP      None             <none>           6644/TCP                                         8d
ovsdbserver-sb-0               ClusterIP      172.30.234.70    <none>           6642/TCP,6644/TCP                                8d
placement-internal             LoadBalancer   172.30.125.87    172.17.0.80      8778:30116/TCP                                   8d
placement-public               ClusterIP      172.30.96.9      <none>           8778/TCP                                         8d
rabbitmq                       LoadBalancer   172.30.212.181   172.17.0.85      5671:32676/TCP,15671:32495/TCP,15691:30561/TCP   8d
rabbitmq-cell1                 LoadBalancer   172.30.30.229    172.17.0.86      5671:31108/TCP,15671:31066/TCP,15691:31831/TCP   8d
rabbitmq-cell1-nodes           ClusterIP      None             <none>           4369/TCP,25672/TCP                               8d
rabbitmq-nodes                 ClusterIP      None             <none>           4369/TCP,25672/TCP                               8d
$
```
Note that the example CRD has manila `enabled: false` but the service
was created prior to disable so the service is in the output below
even though Manila is not used.
```
$ oc get route
NAME                           HOST/PORT                                                       PATH   SERVICES                       PORT                           TERMINATION          WILDCARD
cinder-public                  cinder-public-openstack.apps.ocp.openstack.lab                         cinder-public                  cinder-public                  reencrypt/Redirect   None
glance-default-public          glance-default-public-openstack.apps.ocp.openstack.lab                 glance-default-public          glance-default-public          reencrypt/Redirect   None
horizon                        horizon-openstack.apps.ocp.openstack.lab                               horizon                        horizon                        reencrypt/Redirect   None
keystone-public                keystone-public-openstack.apps.ocp.openstack.lab                       keystone-public                keystone-public                reencrypt/Redirect   None
manila-public                  manila-public-openstack.apps.ocp.openstack.lab                         manila-public                  manila-public                  reencrypt/Redirect   None
neutron-public                 neutron-public-openstack.apps.ocp.openstack.lab                        neutron-public                 neutron-public                 reencrypt/Redirect   None
nova-novncproxy-cell1-public   nova-novncproxy-cell1-public-openstack.apps.ocp.openstack.lab          nova-novncproxy-cell1-public   nova-novncproxy-cell1-public   reencrypt/Redirect   None
nova-public                    nova-public-openstack.apps.ocp.openstack.lab                           nova-public                    nova-public                    reencrypt/Redirect   None
placement-public               placement-public-openstack.apps.ocp.openstack.lab                      placement-public               placement-public               reencrypt/Redirect   None
$
```

Note that this example used a local storage class which supports RWX,
but that RWX is not required.
```
$ oc get pvc
NAME                                              STATUS   VOLUME                     CAPACITY   ACCESS MODES   STORAGECLASS    AGE
glance-conversion-glance-default-external-api-0   Bound    local-storage11-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
glance-conversion-glance-default-external-api-1   Bound    local-storage08-master-0   10Gi       RWO,ROX,RWX    local-storage   8d
glance-conversion-glance-default-external-api-2   Bound    local-storage05-master-1   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-az1-edge-api-0                      Bound    local-storage02-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-az1-edge-api-1                      Bound    local-storage12-master-0   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-az1-edge-api-2                      Bound    local-storage12-master-1   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-az2-edge-api-0                      Bound    local-storage09-master-1   10Gi       RWO,ROX,RWX    local-storage   6d18h
glance-glance-az2-edge-api-1                      Bound    local-storage03-master-0   10Gi       RWO,ROX,RWX    local-storage   6d18h
glance-glance-az2-edge-api-2                      Bound    local-storage08-master-2   10Gi       RWO,ROX,RWX    local-storage   6d18h
glance-glance-default-external-api-0              Bound    local-storage05-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-default-external-api-1              Bound    local-storage01-master-0   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-default-external-api-2              Bound    local-storage10-master-1   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-default-internal-api-0              Bound    local-storage08-master-1   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-default-internal-api-1              Bound    local-storage09-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
glance-glance-default-internal-api-2              Bound    local-storage05-master-0   10Gi       RWO,ROX,RWX    local-storage   8d
mysql-db-openstack-cell1-galera-0                 Bound    local-storage12-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
mysql-db-openstack-cell1-galera-1                 Bound    local-storage03-master-1   10Gi       RWO,ROX,RWX    local-storage   8d
mysql-db-openstack-cell1-galera-2                 Bound    local-storage02-master-0   10Gi       RWO,ROX,RWX    local-storage   8d
mysql-db-openstack-galera-0                       Bound    local-storage03-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
mysql-db-openstack-galera-1                       Bound    local-storage11-master-0   10Gi       RWO,ROX,RWX    local-storage   8d
mysql-db-openstack-galera-2                       Bound    local-storage06-master-1   10Gi       RWO,ROX,RWX    local-storage   8d
ovndbcluster-nb-etc-ovn-ovsdbserver-nb-0          Bound    local-storage01-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
ovndbcluster-sb-etc-ovn-ovsdbserver-sb-0          Bound    local-storage07-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
persistence-rabbitmq-cell1-server-0               Bound    local-storage10-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
persistence-rabbitmq-cell1-server-1               Bound    local-storage04-master-1   10Gi       RWO,ROX,RWX    local-storage   8d
persistence-rabbitmq-cell1-server-2               Bound    local-storage09-master-0   10Gi       RWO,ROX,RWX    local-storage   8d
persistence-rabbitmq-server-0                     Bound    local-storage04-master-2   10Gi       RWO,ROX,RWX    local-storage   8d
persistence-rabbitmq-server-1                     Bound    local-storage01-master-1   10Gi       RWO,ROX,RWX    local-storage   8d
persistence-rabbitmq-server-2                     Bound    local-storage07-master-0   10Gi       RWO,ROX,RWX    local-storage   8d
$
```
