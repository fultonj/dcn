#!/usr/bin/env python3

# ./post-ceph-azn.py post-ceph-az1-temp.yaml post-ceph-az1.yaml \
#    --ceph-secret az0_ceph_secret.yaml --control-plane-cr control-plane-cr.yaml

import argparse
import base64
import configparser
import yaml

from io import StringIO


parser = argparse.ArgumentParser(
    description='Copy SRC to DST but change DST for DCN deployment azN. '
                'The CRs in DST will deploy a new data plane in azN and '
                'update the existing control plane. When SRC is parsed, '
                'keep all dataplane related CRs so that new compute nodes '
                'are created in azN and configured to use ceph backend in azN. '
                'Because we do not want to deploy a new control plane and only '
                'update it, we need to provide CRs from the original control '
                'plane and then patch them with the data in SRC. '
                'Extract data from SRC needed to add a new glance '
                'edge instance with two backends (ceph az0 and azN) and a '
                'new cinder-volume instanace using the ceph azN backend. '
                'A patched ceph-conf-secret and ControlPlane CR (based on the '
                'ones passed with --ceph-secret and --control-plane-cr) will be '
                'included in the DST file.')
parser.add_argument('src', type=str, help='path to source file')
parser.add_argument('dst', type=str, help='path to desination file')
parser.add_argument('--num', type=int, default=1,
                    help='number N of the AZ, e.g. 1 for "az1" (default: 1)')
parser.add_argument('--ceph-secret', type=str,
                    help='path to the ceph-conf-files secret file (ceph secret in SRC will be appended)')
parser.add_argument('--control-plane-cr', type=str,
                    help='path to the control plane CR file (new glance and cinder-volume in SRC will be added)')
args = parser.parse_args()


def split_sections(filename):
    sections = []
    current_section = []
    with open(filename, 'r') as file:
        for line in file:
            # could not just split on '---' since
            # more yaml is embedded in a var
            if line.startswith('---'):
                if current_section:
                    sections.append(current_section)
                    current_section = []
            else:
                current_section.append(line)

        if current_section:
            sections.append(current_section)
    return sections


def append_to_ceph_conf(src, additions, num):
    # Read src into a dict and return it with additions appended
    # Also, update all ceph configuration files to have a [client]
    # section with 'keyring=/etc/ceph/<name>.client.openstack.keyring'.
    # This is necessary for openstack rbd clients to know WHICH openstack
    # keyring to use for each Ceph cluster.
    with open(src, 'r') as src_yaml_file:
        secret = yaml.safe_load(src_yaml_file)
        # append additions to secret['data']
        for old_file_name, file_value_64 in additions.items():
            # is it a bug these files always start with ceph?
            file_name = old_file_name.replace("ceph", "az" + str(num))
            secret['data'][file_name] = file_value_64

        # file_names are updated, time to add a keyring line in [client] section
        for file_name, file_value_64 in secret['data'].items():
            if file_name == "ceph.conf" or file_name == "az" + str(num) + ".conf":
                file_value = base64.b64decode(file_value_64)
                cfg = configparser.ConfigParser()
                cfg.read_string(file_value.decode('utf-8'))
                if 'client' not in cfg:
                    cfg['client'] = {}
                if 'keyring' not in cfg['client']:
                    # if there is no keyring set, then set it
                    cfg['client']['keyring'] = "/etc/ceph/" +\
                        file_name.replace('.conf', '') +\
                        ".client.openstack.keyring"
                str_config = StringIO()
                cfg.write(str_config)
                str_config.seek(0)
                conf_value = str_config.read().encode('utf-8')
                secret['data'][file_name] = base64.b64encode(conf_value)

    return secret


def glance_conf_helper(az0_conf, azn_conf, backend_list):
    # return new multibackend glance INI config as string based on parameters
    new_cfg = configparser.ConfigParser()

    # Either:
    #   1. build new [az0] section and append to it
    # OR
    #   2. keep existing [az0] section (and others) and append to it
    # Determine which by examining what is in az0_conf
    az0_cfg = configparser.ConfigParser()
    az0_cfg.read_string(az0_conf)
    have_az0 = False
    if 'az0' in az0_cfg.sections() and backend_list[0] == 0:
        # we only want to build on az0...
        # if it requested first in list (default) and...
        # if we already have az0
        have_az0 = True

    if not have_az0:
        # build new by adding universal settings
        new_cfg['DEFAULT']['enabled_import_methods'] = "[web-download,copy-image,glance-direct]"
        # use max, because set_az0_glance_conf and set_azn_glance_conf
        # reverse the order of backend_list but new one should be the max
        new_cfg['DEFAULT']['enabled_backends'] = "az0:rbd,az" + str(max(backend_list)) + ":rbd"

        if 'glance_store' not in new_cfg:
            new_cfg['glance_store'] = {}
        # The default backend is the first item on backend_list
        new_cfg['glance_store']['default_backend'] = "az" + str(backend_list[0])
    else:
        # set new_cfg to what we have already
        new_cfg = az0_cfg
        # extended the enabled backends list
        # see "use max" comment above
        new_cfg['DEFAULT']['enabled_backends'] += ",az" + str(max(backend_list)) + ":rbd"
        # only add azN
        last = len(backend_list)-1
        backend_list = [backend_list[last]]

    old_cfg = configparser.ConfigParser()
    # add backends based on order of backend_list
    for n in backend_list:
        az_n = "az" + str(n)
        if n == 0:
            old_cfg.read_string(az0_conf)
        else:
            old_cfg.read_string(azn_conf)
        if az_n not in new_cfg:
            new_cfg[az_n] = {}
        if 'default_backend' in old_cfg:
            for k, v in old_cfg['default_backend'].items():
                if k != "enabled_backends":
                    if k == "store_description":
                        # append the AZ to the description for readability
                        new_cfg[az_n][k] = "\"" + az_n + " " + v.replace('"', '') + "\""
                    else:
                        new_cfg[az_n][k] = v

    # return new_cfg, but wrap it as a string (str_config)
    str_config = StringIO()
    new_cfg.write(str_config)
    str_config.seek(0)
    return str_config.read()


def set_az0_glance_conf(az0_conf, azn_conf, num):
    # return INI file as a string
    # set az0 as default
    # add azN as nth backend
    # IF az0 already contains K other AZs
    #   (for azK for 0 < K < N), then keep them
    #   and append azN
    backend_list = [0, num]
    return glance_conf_helper(az0_conf, azn_conf, backend_list)


def set_azn_glance_conf(az0_conf, azn_conf, num):
    # return INI config as a string
    # set azN as default
    # add az0 as second backend
    backend_list = [num, 0]
    return glance_conf_helper(az0_conf, azn_conf, backend_list)


def get_next_lb_ip(over, num):
    # az0 has the default metallb IP
    # we're adding azN which kustomize will have set to the same IP.
    # So we need to set a different IP from the ipaddresspool as per:
    #   'oc get ipaddresspool -n metallb-system'
    # which is not in use as per:
    #   'oc get ipaddresspool -n metallb-system'
    # For now I'll just assume num makes it unique enough
    ip = over['service']['internal']['metadata']['annotations']\
          ['metallb.universe.tf/loadBalancerIPs']
    octets = ip.split('.')
    octets[3] = str(int(octets[3]) + num)
    over['service']['internal']['metadata']['annotations']['metallb.universe.tf/loadBalancerIPs'] = '.'.join(octets)

    return over


def workaround_glance_ceph_conf(add_glance, cinder_config):
    # kluge.... PR1130 makes ci-framework correctly set ceph_conf
    # for cinder (and nova) but not for glance. This is a quick
    # workaround to get a fast POC. I know cinder has the correct
    # value for any of N AZ deployments, so set glance to use the
    # same one (make add_glance have the correct value).
    # Others not affected since they're only using 'ceph' and one AZ
    # https://github.com/openstack-k8s-operators/ci-framework/pull/1130

    # get a copy cinder's ceph conf (the correct ceph conf)
    cinder_cp = configparser.ConfigParser()
    cinder_cp.read_string(cinder_config)
    ceph_conf = cinder_cp['ceph']['rbd_ceph_conf']

    # get a copy of glance's customServiceConfig
    glance_config = add_glance['template']['customServiceConfig']
    glance_cp = configparser.ConfigParser()
    glance_cp.read_string(glance_config)
    # set the copy to have the correct ceph conf
    glance_cp['default_backend']['rbd_store_ceph_conf'] = ceph_conf

    # convert the customServiceConfig back to a string
    str_config = StringIO()
    glance_cp.write(str_config)
    str_config.seek(0)
    # set add_glance's customServiceConfig to the updated copy
    add_glance['template']['customServiceConfig'] = str_config.read()

    return add_glance


def add_cinder_az(cfg, az):
    # return the Cinder INI cfg which was passed as input
    # but with additional AZ-related settings
    cinder_cp = configparser.ConfigParser()
    cinder_cp.read_string(cfg['customServiceConfig'])
    if 'DEFAULT' not in cinder_cp:
        cinder_cp['DEFAULT'] = {}
    # Relying on convention, confirm with:
    # `oc describe glance glance | grep 'API Endpoint' -C 2`
    glance_endpoint = "https://glance-" + az + "-internal.openstack.svc:9292"
    cinder_cp['DEFAULT']['glance_api_servers'] = glance_endpoint

    cinder_cp['ceph']['rbd_cluster_name'] = az
    cinder_cp['ceph']['backend_availability_zone'] = az

    # convert the customServiceConfig back to a string
    str_config = StringIO()
    cinder_cp.write(str_config)
    str_config.seek(0)
    # set cfg's customServiceConfig to the updated copy
    cfg['customServiceConfig'] = str_config.read()

    return cfg

    
def append_to_control_plane(src, add_cinder, add_glance, num):
    # read src into a dict and return it with cinder and glance appended
    # add_cinder (additional cinder backend) and add_glance (additional
    # glance backend) are new configurations for AZn
    with open(src, 'r') as src_yaml_file:
        cp = yaml.safe_load(src_yaml_file)
        # Create key for new additions based on the AZ number
        # These keys default to 'ceph' or 'default' (keep SRC like that?)
        key = "az" + str(num)

        # 1. append add_cinder to control plane (cp) cinderVolumes dict
        cp['spec']['cinder']['template']['cinderVolumes'][key] = \
            add_cinder_az(add_cinder['template']['cinderVolumes']['ceph'], key)
        # print(cp['spec']['cinder']['template']['cinderVolumes'])

        # workaround glitch in add_glance source before using
        add_glance = workaround_glance_ceph_conf(add_glance, \
            add_cinder['template']['cinderVolumes']['ceph']['customServiceConfig'])

        # 2. append add_glance to control plane (cp) glanceAPIs dict but before that...
        # a. Rearrange structure for multiple customServiceConfigs if we are on az1
        if 'customServiceConfig' in cp['spec']['glance']['template']:
            az0_glance_conf = cp['spec']['glance']['template']['customServiceConfig']
            del(cp['spec']['glance']['template']['customServiceConfig'])
        elif 'glanceAPIs' in cp['spec']['glance']['template']:
            # We already have multiple customServiceConfigs
            # "az0_glance_conf" refers to the default glance
            # who's INI might contain backends for AZ(n-1), AZ(n-2), ..., AZ0
            # We still want to add AZn (the add_glance dict) to it though
            if 'default' in cp['spec']['glance']['template']['glanceAPIs']:
                az0_glance_conf = cp['spec']['glance']['template']['glanceAPIs']['default']['customServiceConfig']
            else:
                print("WARNING: no default backend in glanceAPIs list")
        else:
            print("WARNING: glanceAPIs or customServiceConfig missing from glance")

        azn_glance_conf = add_glance['template']['customServiceConfig']
        cp['spec']['glance']['template']['glanceAPIs']['default']['customServiceConfig'] =\
            set_az0_glance_conf(az0_glance_conf, azn_glance_conf, num)
        add_glance['template']['glanceAPIs']['default']['customServiceConfig'] =\
            set_azn_glance_conf(az0_glance_conf, azn_glance_conf, num)

        # b. keep glance overrides per service but increment azN's LB IP
        add_glance['template']['glanceAPIs']['default']['override'] =\
            get_next_lb_ip(add_glance['template']['glanceAPIs']['default']['override'], num)

        # c. Add items to az0 glance
        cp['spec']['glance']['template']['glanceAPIs']['default']['type'] = 'split'
        cp['spec']['glance']['template']['glanceAPIs']['default']['preserveJobs'] = False
        
        # d. Add items to azN glance
        add_glance['template']['glanceAPIs']['default']['type'] = 'edge'
        add_glance['template']['glanceAPIs']['default']['preserveJobs'] = False
        
        # e. Add other items to main glance tree
        cp['spec']['glance']['template']['serviceUser'] = "glance"
        cp['spec']['glance']['template']['databaseInstance'] = "openstack"
        cp['spec']['glance']['template']['databaseAccount'] = "glance"
        cp['spec']['glance']['template']['keystoneEndpoint'] = "default"

        # Uncomment to remove apiOverrides
        # del(cp['spec']['glance']['apiOverrides'])

        # append azN to glanceAPIs dict (azN in add_glance is no longer called 'default')
        cp['spec']['glance']['template']['glanceAPIs'][key] =\
            add_glance['template']['glanceAPIs']['default']

        # debug glance re-structure
        # print(yaml.safe_dump(cp['spec']['glance'], indent=2))
        
    return cp


def add_nova_az(data, num):
    # Update 03-ceph-nova.conf configmap with DCN config
    nova_cp = configparser.ConfigParser()
    nova_cp.read_string(data['data']['03-ceph-nova.conf'])

    nova_cp['libvirt']['images_rbd_glance_store_name'] = "az" + str(num)
    nova_cp['libvirt']['hw_disk_discard'] = 'unmap'
    nova_cp['libvirt']['volume_use_multipath'] = 'False'

    if 'glance' not in nova_cp:
        nova_cp['glance'] = {}
    # Relying on convention, confirm with:
    # `oc describe glance glance | grep 'API Endpoint' -C 2`
    glance_endpoint = "https://glance-az" + str(num) + "-internal.openstack.svc:9292"
    nova_cp['glance']['endpoint_override'] = glance_endpoint
    nova_cp['glance']['valid_interfaces'] = 'internal'

    if 'cinder' not in nova_cp:
        nova_cp['cinder'] = {}
    nova_cp['cinder']['cross_az_attach'] = 'False'
    nova_cp['cinder']['catalog_info'] = 'volumev3:cinderv3:internalURL'

    str_config = StringIO()
    nova_cp.write(str_config)
    str_config.seek(0)
    # set 03-ceph-nova.conf to the updated copy
    data['data']['03-ceph-nova.conf'] = str_config.read()

    return data


sections = split_sections(args.src)
with open(args.dst, 'w') as f:
    for section in sections:
        # parse each section and determine how to process it based on up to 3 kinds
        data = yaml.safe_load(''.join(section))
        # 0. CEPH CONF SECRETS
        if data['kind'] == 'Secret' and \
          data['metadata']['name'] == 'ceph-conf-files':
            if args.ceph_secret is None:
                print("--ceph-secret not passed; unable to created patched version")
            else:
                # redefine ceph-conf-files data with args.ceph_secret and append data from src
                data = append_to_ceph_conf(args.ceph_secret, data['data'], args.num)
                # write upated ceph secret data to DST
                f.write('---\n')
                f.write(yaml.safe_dump(data, indent=2))
        # exclude all other secrets (ceph-conf-files handled above)
        elif data['kind'] != 'Secret':
            # 1. CONTROL PLANE
            if data['kind'] == 'OpenStackControlPlane':
                if args.control_plane_cr is None:
                    print("--control-plane-cr not passed; unable to created patched version")
                else:
                    # For the control plane I want:
                    #   - a new glance edge instance with two backends (az0 and azN)
                    #   - a new cinder-volume instance with its own new backend
                    #
                    # Redefine ControlPlane CR in data with args.control_plane_cr and
                    # append data from cinder and glance
                    data = append_to_control_plane(args.control_plane_cr, \
                                            data['spec']['cinder'], \
                                            data['spec']['glance'], \
                                            args.num)
                    # write updated control plane data to DST
                    f.write('---\n')
                    f.write(yaml.safe_dump(data, indent=2))
            else:
                # 2. DATA PLANE
                # For the data plane:
                #   - deploy the same genereated post ceph CRs
                #   - but rename all dataplane CRs to append azN
                data['metadata']['name'] += "-az" + str(args.num)
                # rename nodeSets, ceph-nova config map and services to match
                if data['kind'] == 'OpenStackDataPlaneDeployment':
                    data['spec']['nodeSets'][0] += "-az" + str(args.num)
                if data['kind'] == 'OpenStackDataPlaneService':
                    data['spec']['dataSources'][0]['configMapRef']['name'] += "-az" + str(args.num)
                if data['kind'] == 'ConfigMap' and \
                   data['metadata']['name'] == "ceph-nova" + "-az" + str(args.num):
                    data = add_nova_az(data, args.num)
                if data['kind'] == 'OpenStackDataPlaneNodeSet':
                    for i in range(0, len(data['spec']['services'])):
                        if data['spec']['services'][i] == "nova-custom-ceph":
                            data['spec']['services'][i] += "-az" + str(args.num)
                # write each dataplane section to DST
                f.write('---\n')
                f.write(yaml.safe_dump(data, indent=2))
