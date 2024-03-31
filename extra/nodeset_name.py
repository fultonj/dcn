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


sections = split_sections(args.src)
with open(args.dst, 'w') as f:
    for section in sections:
        parsed_data = yaml.safe_load(''.join(section))
        if parsed_data['kind'] != 'Secret':
            parsed_data['metadata']['name'] += "-az" + str(args.num)
            if parsed_data['kind'] == 'OpenStackDataPlaneDeployment':
                parsed_data['spec']['nodeSets'][0] += "-az" + str(args.num)
            f.write('---\n')
            f.write(yaml.safe_dump(parsed_data, indent=2))
