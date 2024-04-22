#!/usr/bin/env python3

import argparse
import yaml

parser = argparse.ArgumentParser(
    description='Copy SRC to DST but change name to append "-azN". '
                'For example, in a call like this '
                '`node_filter.py src.yaml dst.yaml --num 2`, '
                'dst.yaml will have the same content as src.yaml '
                'but any kind of OpenStackDataPlaneNodeSet '
                'or OpenStackDataPlaneDeployment would have its '
                'metadata name changed from, e.g. '
                '"edpm-deployment-pre-ceph" to '
                '"edpm-deployment-pre-ceph-az2" in dst-values.yaml. '
                'Also, any kind of secret will be removed.')
parser.add_argument('src', type=str, help='path to source file')
parser.add_argument('dst', type=str, help='path to desination file')
parser.add_argument('--num', type=int, default=1,
                    help='number of the AZ, e.g. 1 for "az1" (default: 1)')
parser.add_argument('--no-ceph', action='store_true',
                    help='if ceph is not being used by the EDPM node(s), '
                         'pass this flag in order to populate the full '
                         'service list and remove unnecessary ceph '
                         'variables. (default: false)')

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


def no_ceph_services_list(svcs):
    # return the services list with it
    # extended to include new services
    # which would normally only happen
    # after ceph is deployed, also remove
    # the ceph-hci-pre service.
    svcs.remove('ceph-hci-pre')
    new_svcs = [
        'install-certs',
        'ovn',
        'neutron-metadata',
        'libvirt',
        'nova'
    ]
    svcs.extend(new_svcs)
    return svcs


def no_ceph_ansible_vars(vdict):
    # return the dictionary of ansible values but
    # without the variables in the remove list
    new_vdict = {}
    remove = [
        'edpm_ceph_hci_pre_enabled_services',
        'storage_mgmt_cidr',
        'storage_mgmt_host_routes',
        'storage_mgmt_mtu',
        'storage_mgmt_vlan_id',
    ]
    for k, v in vdict.items():
        if k not in remove:
            new_vdict[k] = v
    return new_vdict


def no_ceph_mgmt_network(nodes):
    # return the dictionary of ndoes but
    # each node's network list will not have
    # the storagemgmt network
    new_nodes = {}
    for node, data in nodes.items():
        new_networks = []
        for net in data['networks']:
            if net['name'] != 'storagemgmt':
                new_networks.append(net)
        data['networks'] = new_networks
        new_nodes[node] = data

    return nodes


sections = split_sections(args.src)
with open(args.dst, 'w') as f:
    for section in sections:
        parsed_data = yaml.safe_load(''.join(section))
        if parsed_data['kind'] != 'Secret':
            if args.no_ceph:
                parsed_data['metadata']['name'] =\
                    parsed_data['metadata']['name'].replace('-pre-ceph', '')
            parsed_data['metadata']['name'] += "-az" + str(args.num)
            if parsed_data['kind'] == 'OpenStackDataPlaneDeployment':
                parsed_data['spec']['nodeSets'][0] += "-az" + str(args.num)
            if args.no_ceph and parsed_data['kind'] == 'OpenStackDataPlaneNodeSet':
                parsed_data['spec']['services'] =\
                    no_ceph_services_list(parsed_data['spec']['services'])
                parsed_data['spec']['nodeTemplate']['ansible']['ansibleVars'] =\
                    no_ceph_ansible_vars(parsed_data['spec']['nodeTemplate']\
                                         ['ansible']['ansibleVars'])
                parsed_data['spec']['nodes'] =\
                    no_ceph_mgmt_network(parsed_data['spec']['nodes'])
            f.write('---\n')
            f.write(yaml.safe_dump(parsed_data, indent=2))
