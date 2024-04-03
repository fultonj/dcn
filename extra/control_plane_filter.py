#!/usr/bin/env python

import argparse
import yaml

parser = argparse.ArgumentParser(
    description='Copy SRC to DST but drop all CRs '
                'except the first of kind OpenStackControlPlane')
parser.add_argument('src', type=str, help='path to source file')
parser.add_argument('dst', type=str, help='path to desination file')
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
for section in sections:
    data = yaml.safe_load(''.join(section))
    if data['kind'] == 'OpenStackControlPlane':
        with open(args.dst, 'w') as dst_yaml_file:
            yaml.dump(data, dst_yaml_file, indent=2)
        break
