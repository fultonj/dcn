#!/usr/bin/env python

import argparse
import yaml


def filter_nodes(nodes, keep):
    for node in list(nodes.keys()):
        if node not in keep:
            del nodes[node]    


parser = argparse.ArgumentParser(
    description='Copy SRC to DST but only keep '
                'nodes ending in BEG <= X <= END. '
                'For example, in a call like this '
                '`node_filter.py src-values.yaml dst-values.yaml` '
                'dst-values.yaml will have the same content but only '
                'nodes edpm-compute-0, edpm-compute-1, edpm-compute-2 '
                'will be in dst-values.yaml. '
                'Any other nodes will be removed.')
parser.add_argument('src', type=str, help='path to source file')
parser.add_argument('dst', type=str, help='path to desination file')
parser.add_argument('--beg', type=int, default=0,
                    help='beginning of the range of node suffixes (default: 0)')
parser.add_argument('--end', type=int, default=2,
                    help='ending of the range of node suffixes (default: 2)')
args = parser.parse_args()

keep = []
for i in range(args.beg, args.end+1):
    keep.append('edpm-compute-' + str(i))

with open(args.src, 'r') as src_yaml_file:
    content = yaml.safe_load(src_yaml_file)
    filter_nodes(content['data']['nodeset']['nodes'], keep)
    filter_nodes(content['data']['nodeset']['ansible']['ansibleVars']\
                 ['edpm_network_config_os_net_config_mappings'], keep)
    with open(args.dst, 'w') as dst_yaml_file:
        yaml.dump(content, dst_yaml_file, indent=2)
