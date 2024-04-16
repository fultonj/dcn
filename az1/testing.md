Reproducing the steps from 
[Storage and Distributed Compute Nodes: Bringing Cinder persistent volumes to the edge](https://www.redhat.com/en/blog/storage-and-distributed-compute-nodes-bringing-cinder-persistent-volumes-edge)
but in an 18 deployment.

Glance is configured for az0 and az1.
```
$ glance stores-info
+----------+----------------------------------------------------------------------------------+
| Property | Value                                                                            |
+----------+----------------------------------------------------------------------------------+
| stores   | [{"id": "az0", "description": "az0 RBD backend", "default": "true"}, {"id":      |
|          | "az1", "description": "az1 RBD backend"}]                                        |
+----------+----------------------------------------------------------------------------------+
$
```
Uploading cirros to the default backend (az0):
```
    glance image-create \
           --disk-format raw \
           --container-format bare \
           --name cirros-0.5.2-x86_64-disk.img \
           --file cirros \
           --store az0
```
produces:
```
+------------------+----------------------------------------------------------------------------------+
| Property         | Value                                                                            |
+------------------+----------------------------------------------------------------------------------+
| checksum         | b874c39491a2377b8490f5f1e89761a4                                                 |
| container_format | bare                                                                             |
| created_at       | 2024-04-15T13:55:17Z                                                             |
| disk_format      | raw                                                                              |
| id               | e9c32c40-d8a6-48c5-9eaa-f9a375870dff                                             |
| min_disk         | 0                                                                                |
| min_ram          | 0                                                                                |
| name             | cirros                                                                           |
| os_hash_algo     | sha512                                                                           |
| os_hash_value    | 6b813aa46bb90b4da216a4d19376593fa3f4fc7e617f03a92b7fe11e9a3981cbe8f0959dbebe3622 |
|                  | 5e5f53dc4492341a4863cac4ed1ee0909f3fc78ef9c3e869                                 |
| os_hidden        | False                                                                            |
| owner            | 208b1be01846439d801c34348c4351e2                                                 |
| protected        | False                                                                            |
| size             | 16300544                                                                         |
| status           | active                                                                           |
| stores           | az0                                                                              |
| tags             | []                                                                               |
| updated_at       | 2024-04-15T13:55:20Z                                                             |
| virtual_size     | 16300544                                                                         |
| visibility       | shared                                                                           |
+------------------+----------------------------------------------------------------------------------+
```

cirros-0.5.2-x86_64-disk.img should only be on AZ0
```
$ glance image-show e9c32c40-d8a6-48c5-9eaa-f9a375870dff | grep stores
| stores           | az0                                                                              |
$
```

Running `rbd -p images ls -l` on compute-0
```
NAME                                       SIZE    PARENT  FMT  PROT  LOCK
e9c32c40-d8a6-48c5-9eaa-f9a375870dff       16 MiB            2            
e9c32c40-d8a6-48c5-9eaa-f9a375870dff@snap  16 MiB            2  yes       
```
Import the image to AZ1.
```
$ glance image-import e9c32c40-d8a6-48c5-9eaa-f9a375870dff --stores az1 --import-method copy-image
+-----------------------+----------------------------------------------------------------------------------+
| Property              | Value                                                                            |
+-----------------------+----------------------------------------------------------------------------------+
| checksum              | b874c39491a2377b8490f5f1e89761a4                                                 |
| container_format      | bare                                                                             |
| created_at            | 2024-04-15T13:55:17Z                                                             |
| disk_format           | raw                                                                              |
| id                    | e9c32c40-d8a6-48c5-9eaa-f9a375870dff                                             |
| min_disk              | 0                                                                                |
| min_ram               | 0                                                                                |
| name                  | cirros                                                                           |
| os_glance_import_task | 691ba080-a8ce-4b65-b9bc-8d39c0abb90f                                             |
| os_hash_algo          | sha512                                                                           |
| os_hash_value         | 6b813aa46bb90b4da216a4d19376593fa3f4fc7e617f03a92b7fe11e9a3981cbe8f0959dbebe3622 |
|                       | 5e5f53dc4492341a4863cac4ed1ee0909f3fc78ef9c3e869                                 |
| os_hidden             | False                                                                            |
| owner                 | 208b1be01846439d801c34348c4351e2                                                 |
| protected             | False                                                                            |
| size                  | 16300544                                                                         |
| status                | active                                                                           |
| stores                | az0                                                                              |
| tags                  | []                                                                               |
| updated_at            | 2024-04-15T13:55:20Z                                                             |
| virtual_size          | 16300544                                                                         |
| visibility            | shared                                                                           |
+-----------------------+----------------------------------------------------------------------------------+
```

We see it is importing.
```
$ glance image-show e9c32c40-d8a6-48c5-9eaa-f9a375870dff | grep stores
| os_glance_importing_to_stores | az1                                                                              |
| stores                        | az0                                                                              |
$ 
```
We see it arrived as we can see it on the AZ1 ceph cluster.

Running `rbd -p images ls -l` on compute-3
```
NAME                                       SIZE    PARENT  FMT  PROT  LOCK
e9c32c40-d8a6-48c5-9eaa-f9a375870dff       16 MiB            2            
e9c32c40-d8a6-48c5-9eaa-f9a375870dff@snap  16 MiB            2  yes       
```
Create a VM in AZ1 from the copied image.
```
$ openstack server create --flavor c1 --image e9c32c40-d8a6-48c5-9eaa-f9a375870dff --nic net-id=private vm1-az1 --availability-zone az1
+-------------------------------------+-----------------------------------------------+
| Field                               | Value                                         |
+-------------------------------------+-----------------------------------------------+
| OS-DCF:diskConfig                   | MANUAL                                        |
| OS-EXT-AZ:availability_zone         | az1                                           |
| OS-EXT-SRV-ATTR:host                | None                                          |
| OS-EXT-SRV-ATTR:hypervisor_hostname | None                                          |
| OS-EXT-SRV-ATTR:instance_name       |                                               |
| OS-EXT-STS:power_state              | NOSTATE                                       |
| OS-EXT-STS:task_state               | scheduling                                    |
| OS-EXT-STS:vm_state                 | building                                      |
| OS-SRV-USG:launched_at              | None                                          |
| OS-SRV-USG:terminated_at            | None                                          |
| accessIPv4                          |                                               |
| accessIPv6                          |                                               |
| addresses                           |                                               |
| adminPass                           | fpJ2Yn3wbHPn                                  |
| config_drive                        |                                               |
| created                             | 2024-04-15T14:05:23Z                          |
| flavor                              | c1 (740e31e0-2cff-4151-9bf9-cf5de6417102)     |
| hostId                              |                                               |
| id                                  | 4e65eb7f-9482-4629-85e6-295aca3f51bb          |
| image                               | cirros (e9c32c40-d8a6-48c5-9eaa-f9a375870dff) |
| key_name                            | None                                          |
| name                                | vm1-az1                                       |
| progress                            | 0                                             |
| project_id                          | 208b1be01846439d801c34348c4351e2              |
| properties                          |                                               |
| security_groups                     | name='default'                                |
| status                              | BUILD                                         |
| updated                             | 2024-04-15T14:05:23Z                          |
| user_id                             | bbe045061a384f31bc37ecdd84e2abe9              |
| volumes_attached                    |                                               |
+-------------------------------------+-----------------------------------------------+
$
```
The VM is active.
```
$ openstack server list
+--------------------------------------+---------+--------+----------------------+--------+--------+
| ID                                   | Name    | Status | Networks             | Image  | Flavor |
+--------------------------------------+---------+--------+----------------------+--------+--------+
| 4e65eb7f-9482-4629-85e6-295aca3f51bb | vm1-az1 | ACTIVE | private=192.168.0.82 | cirros | c1     |
+--------------------------------------+---------+--------+----------------------+--------+--------+
```
Running `rbd -p vms ls -l` on compute-3 in AZ1 we see the VM object
is from its parent image object.
```
NAME                                              SIZE     PARENT                                            FMT  PROT  LOCK
4e65eb7f-9482-4629-85e6-295aca3f51bb_disk          16 MiB  images/e9c32c40-d8a6-48c5-9eaa-f9a375870dff@snap    2            
4e65eb7f-9482-4629-85e6-295aca3f51bb_disk.config  474 KiB                                                      2            
```
Next, create an 8 GB Cinder volume in AZ0 from the cirros image.
```
$ openstack volume create --size 8 vol1-cirros --image e9c32c40-d8a6-48c5-9eaa-f9a375870dff
+---------------------+--------------------------------------+
| Field               | Value                                |
+---------------------+--------------------------------------+
| attachments         | []                                   |
| availability_zone   | nova                                 |
| bootable            | false                                |
| consistencygroup_id | None                                 |
| created_at          | 2024-04-16T19:36:48.859074           |
| description         | None                                 |
| encrypted           | False                                |
| id                  | 5994cfde-9199-4106-84da-11f87d332d1b |
| migration_status    | None                                 |
| multiattach         | False                                |
| name                | vol1-cirros                          |
| properties          |                                      |
| replication_status  | None                                 |
| size                | 8                                    |
| snapshot_id         | None                                 |
| source_volid        | None                                 |
| status              | creating                             |
| type                | __DEFAULT__                          |
| updated_at          | None                                 |
| user_id             | bbe045061a384f31bc37ecdd84e2abe9     |
+---------------------+--------------------------------------+
$
```
Listing Cinder Ceph Pool and Volume List
```
$ openstack volume list
+--------------------------------------+-------------+-----------+------+-------------+
| ID                                   | Name        | Status    | Size | Attached to |
+--------------------------------------+-------------+-----------+------+-------------+
| 5994cfde-9199-4106-84da-11f87d332d1b | vol1-cirros | available |    8 |             |
+--------------------------------------+-------------+-----------+------+-------------+
$
```
Running `rbd -p volumes ls -l` on compute-0 in AZ0. We wee the volume object
and its parent image.
```
NAME                                         SIZE   PARENT                                            FMT  PROT  LOCK
volume-5994cfde-9199-4106-84da-11f87d332d1b  8 GiB  images/e9c32c40-d8a6-48c5-9eaa-f9a375870dff@snap    2            
```
Create VM from volume
```
$ openstack server create --flavor c1 --volume 5994cfde-9199-4106-84da-11f87d332d1b --nic net-id=private vm1-pet
+-------------------------------------+-------------------------------------------+
| Field                               | Value                                     |
+-------------------------------------+-------------------------------------------+
| OS-DCF:diskConfig                   | MANUAL                                    |
| OS-EXT-AZ:availability_zone         |                                           |
| OS-EXT-SRV-ATTR:host                | None                                      |
| OS-EXT-SRV-ATTR:hypervisor_hostname | None                                      |
| OS-EXT-SRV-ATTR:instance_name       |                                           |
| OS-EXT-STS:power_state              | NOSTATE                                   |
| OS-EXT-STS:task_state               | scheduling                                |
| OS-EXT-STS:vm_state                 | building                                  |
| OS-SRV-USG:launched_at              | None                                      |
| OS-SRV-USG:terminated_at            | None                                      |
| accessIPv4                          |                                           |
| accessIPv6                          |                                           |
| addresses                           |                                           |
| adminPass                           | QJ4gUJ8gpVqR                              |
| config_drive                        |                                           |
| created                             | 2024-04-16T19:37:47Z                      |
| flavor                              | c1 (740e31e0-2cff-4151-9bf9-cf5de6417102) |
| hostId                              |                                           |
| id                                  | 789d81f9-aee9-4b5b-ab27-c1934329b4fc      |
| image                               | N/A (booted from volume)                  |
| key_name                            | None                                      |
| name                                | vm1-pet                                   |
| progress                            | 0                                         |
| project_id                          | 208b1be01846439d801c34348c4351e2          |
| properties                          |                                           |
| security_groups                     | name='default'                            |
| status                              | BUILD                                     |
| updated                             | 2024-04-16T19:37:47Z                      |
| user_id                             | bbe045061a384f31bc37ecdd84e2abe9          |
| volumes_attached                    |                                           |
+-------------------------------------+-------------------------------------------+
$
```
The VM in AZ1 was booted from the cinder volume and is active.
```
$ openstack server list
+--------------------------------------+---------+--------+-----------------------+--------------------------+--------+
| ID                                   | Name    | Status | Networks              | Image                    | Flavor |
+--------------------------------------+---------+--------+-----------------------+--------------------------+--------+
| 789d81f9-aee9-4b5b-ab27-c1934329b4fc | vm1-pet | ACTIVE | private=192.168.0.250 | N/A (booted from volume) | c1     |
+--------------------------------------+---------+--------+-----------------------+--------------------------+--------+
$
```
Running `rbd -p vms ls -l` on compute-0. See the disk config on Ceph at default site (az0).
```
NAME                                              SIZE     PARENT  FMT  PROT  LOCK
789d81f9-aee9-4b5b-ab27-c1934329b4fc_disk.config  474 KiB            2            
```

See the volume:
```
$ openstack volume list
+--------------------------------------+-------------+--------+------+----------------------------------+
| ID                                   | Name        | Status | Size | Attached to                      |
+--------------------------------------+-------------+--------+------+----------------------------------+
| 5994cfde-9199-4106-84da-11f87d332d1b | vol1-cirros | in-use |    8 | Attached to vm1-pet on /dev/vda  |
+--------------------------------------+-------------+--------+------+----------------------------------+
$
```
Create snapshot
```
$ openstack server image create --name cirros-snapshot vm1-pet
+------------------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Field            | Value                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
+------------------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| checksum         | d41d8cd98f00b204e9800998ecf8427e                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| container_format | bare                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| created_at       | 2024-04-16T19:40:18Z                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| disk_format      | qcow2                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| file             | /v2/images/41bf3eed-0dd3-439f-b573-7f01c555ee69/file                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| id               | 41bf3eed-0dd3-439f-b573-7f01c555ee69                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| min_disk         | 0                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| min_ram          | 0                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| name             | cirros-snapshot                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| owner            | 208b1be01846439d801c34348c4351e2                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| properties       | base_image_ref='', bdm_v2='True', block_device_mapping='[{"encrypted": null, "device_type": "disk", "encryption_options": null, "device_name": "/dev/vda", "no_device": null, "destination_type": "volume", "encryption_format": null, "guest_format": null, "boot_index": 0, "tag": null, "encryption_secret_uuid": null, "volume_type": null, "source_type": "snapshot", "disk_bus": "virtio", "snapshot_id": "dcb83ded-3873-46ef-969f-7346ce397e1a", "image_id": null, "volume_id": null, "delete_on_termination": false, "volume_size": 8}]', boot_roles='reader,admin,member', hw_cdrom_bus='sata', hw_disk_bus='virtio', hw_input_bus='usb', hw_machine_type='q35', hw_pointer_model='usbtablet', hw_video_model='virtio', hw_vif_model='virtio', os_hash_algo='sha512', os_hash_value='cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e', os_hidden='False', owner_project_name='admin', owner_user_name='admin', root_device_name='/dev/vda', stores='az0' |
| protected        | False                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| schema           | /v2/schemas/image                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| size             | 0                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| status           | active                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| tags             |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| updated_at       | 2024-04-16T19:40:19Z                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| visibility       | private                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
+------------------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
$
```
List the images and now we see the snapshot too.
```
$ openstack image list
+--------------------------------------+-----------------+--------+
| ID                                   | Name            | Status |
+--------------------------------------+-----------------+--------+
| e9c32c40-d8a6-48c5-9eaa-f9a375870dff | cirros          | active |
| 41bf3eed-0dd3-439f-b573-7f01c555ee69 | cirros-snapshot | active |
+--------------------------------------+-----------------+--------+
$
```
A cinder volume snapshot was also created.
```
$ openstack volume snapshot list
+--------------------------------------+------------------------------+-------------+-----------+------+
| ID                                   | Name                         | Description | Status    | Size |
+--------------------------------------+------------------------------+-------------+-----------+------+
| dcb83ded-3873-46ef-969f-7346ce397e1a | snapshot for cirros-snapshot | None        | available |    8 |
+--------------------------------------+------------------------------+-------------+-----------+------+
$
```
Copy the image snapshot from AZ0 to AZ1.
```
$ glance image-import 41bf3eed-0dd3-439f-b573-7f01c555ee69 --stores az1 --import-method copy-image
+-----------------------+----------------------------------------------------------------------------------+
| Property              | Value                                                                            |
+-----------------------+----------------------------------------------------------------------------------+
| base_image_ref        |                                                                                  |
| bdm_v2                | True                                                                             |
| block_device_mapping  | [{"encrypted": null, "device_type": "disk", "encryption_options": null,          |
|                       | "device_name": "/dev/vda", "no_device": null, "destination_type": "volume",      |
|                       | "encryption_format": null, "guest_format": null, "boot_index": 0, "tag": null,   |
|                       | "encryption_secret_uuid": null, "volume_type": null, "source_type": "snapshot",  |
|                       | "disk_bus": "virtio", "snapshot_id": "dcb83ded-3873-46ef-969f-7346ce397e1a",     |
|                       | "image_id": null, "volume_id": null, "delete_on_termination": false,             |
|                       | "volume_size": 8}]                                                               |
| boot_roles            | reader,admin,member                                                              |
| checksum              | d41d8cd98f00b204e9800998ecf8427e                                                 |
| container_format      | bare                                                                             |
| created_at            | 2024-04-16T19:40:18Z                                                             |
| disk_format           | qcow2                                                                            |
| hw_cdrom_bus          | sata                                                                             |
| hw_disk_bus           | virtio                                                                           |
| hw_input_bus          | usb                                                                              |
| hw_machine_type       | q35                                                                              |
| hw_pointer_model      | usbtablet                                                                        |
| hw_video_model        | virtio                                                                           |
| hw_vif_model          | virtio                                                                           |
| id                    | 41bf3eed-0dd3-439f-b573-7f01c555ee69                                             |
| min_disk              | 0                                                                                |
| min_ram               | 0                                                                                |
| name                  | cirros-snapshot                                                                  |
| os_glance_import_task | e89bc6df-2a23-420c-bb26-72fa1a1ab19e                                             |
| os_hash_algo          | sha512                                                                           |
| os_hash_value         | cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0 |
|                       | ff8318d2877eec2f63b931bd47417a81a538327af927da3e                                 |
| os_hidden             | False                                                                            |
| owner                 | 208b1be01846439d801c34348c4351e2                                                 |
| owner_project_name    | admin                                                                            |
| owner_user_name       | admin                                                                            |
| protected             | False                                                                            |
| root_device_name      | /dev/vda                                                                         |
| size                  | 0                                                                                |
| status                | active                                                                           |
| stores                | az0                                                                              |
| tags                  | []                                                                               |
| updated_at            | 2024-04-16T19:40:19Z                                                             |
| virtual_size          | Not available                                                                    |
| visibility            | private                                                                          |
+-----------------------+----------------------------------------------------------------------------------+
$
```
```
$ glance image-show 41bf3eed-0dd3-439f-b573-7f01c555ee69 | grep stores
| os_glance_importing_to_stores |                                                                                  |
| stores                        | az0,az1                                                                          |
$
```
Note that the snapshot is now in store AZ1 too (it was created in AZ0).

The new image at AZ1 may now be copied to other sites, used to create new volumes, booted as new instances and snapshotted.
