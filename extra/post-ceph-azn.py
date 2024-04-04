#!/usr/bin/env python3

# ./post-ceph-azn.py post-ceph-az1-temp.yaml post-ceph-az1.yaml \
#    --ceph-secret az0_ceph_secret.yaml --control-plane-cr control-plane-cr.yaml

import argparse
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
    # read src into a dict and return it with additions appended
    with open(src, 'r') as src_yaml_file:
        secret = yaml.safe_load(src_yaml_file)
        # append additions to secret['data']
        for old_file_name, file_value in additions.items():
            # is it a bug these files always start with ceph?
            file_name = old_file_name.replace("ceph", "az" + str(num))
            secret['data'][file_name] = file_value
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
        # build new by adding settings used for all backends
        if 'glance_store' not in new_cfg:
            new_cfg['glance_store'] = {}
        new_cfg['glance_store']['stores'] = "http,rbd"
        new_cfg['glance_store']['os_region_name'] = "regionOne"
        # The default backend is the first item on backend_list
        new_cfg['glance_store']['default_backend'] = "az" + str(backend_list[0])
    else:
        # set new_cfg to what we have already and then just add azN
        last = len(backend_list)-1
        backend_list = [backend_list[last]]
        new_cfg = az0_cfg

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
                    elif k == "rbd_store_user":
                        # append the AZ dot name to the store user?
                        new_cfg[az_n][k] = az_n + "." + v.replace('"', '')
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

    
def append_to_control_plane(src, add_cinder, add_glance, num):
    # read src into a dict and return it with cinder and glance appended
    with open(src, 'r') as src_yaml_file:
        cp = yaml.safe_load(src_yaml_file)
        # Create key for new additions based on the AZ number
        # These keys default to 'ceph' or 'default' (keep SRC like that?)
        key = "az" + str(num)

        # 1. append add_cinder to control plane (cp) cinderVolumes dict
        cp['spec']['cinder']['template']['cinderVolumes'][key] = \
            add_cinder['template']['cinderVolumes']['ceph']
        # print(cp['spec']['cinder']['template']['cinderVolumes'])

        # 2. append add_glance to control plane (cp) glanceAPIs dict but before that...
        # a. Rearrange structure for multiple customServiceConfigs
        az0_glance_conf = cp['spec']['glance']['template']['customServiceConfig']
        azn_glance_conf = add_glance['template']['customServiceConfig']
        cp['spec']['glance']['template']['glanceAPIs']['default']['customServiceConfig'] =\
            set_az0_glance_conf(az0_glance_conf, azn_glance_conf, num)
        add_glance['template']['glanceAPIs']['default']['customServiceConfig'] =\
            set_azn_glance_conf(az0_glance_conf, azn_glance_conf, num)
        del(cp['spec']['glance']['template']['customServiceConfig'])

        # b. Move overrides to the main glance tree
        override = cp['spec']['glance']['template']['glanceAPIs']['default']['override']
        cp['spec']['glance']['template']['override'] = override
        del(cp['spec']['glance']['template']['glanceAPIs']['default']['override'])
        del(add_glance['template']['glanceAPIs']['default']['override'])

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
                    data['spec']['configMaps'][0] += "-az" + str(args.num)
                if data['kind'] == 'OpenStackDataPlaneNodeSet':
                    for i in range(0, len(data['spec']['services'])):
                        if data['spec']['services'][i] == "nova-custom-ceph":
                            data['spec']['services'][i] += "-az" + str(args.num)
                # write each dataplane section to DST
                f.write('---\n')
                f.write(yaml.safe_dump(data, indent=2))
