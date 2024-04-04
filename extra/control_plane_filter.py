#!/usr/bin/env python

import argparse
import base64
import configparser
import yaml


from io import StringIO


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


def get_fsid():
    ceph_secret = "/home/zuul/az0_ceph_secret.yaml"
    with open(ceph_secret, 'r') as yaml_file:
        data = yaml.safe_load(yaml_file)
        ceph_conf = base64.b64decode(data['data']['ceph.conf'])
        cfg = configparser.ConfigParser()
        cfg.read_string(ceph_conf.decode('utf-8'))
        return cfg['global']['fsid']


def work_around_missing_fsid(data):
    # kluge... I have ci-framework stop early before the
    # FSID can be substituted so I workaround it here
    cfg = configparser.ConfigParser()
    try:
        cfg.read_string(data['spec']['cinder']['template']['cinderVolumes']['ceph']['customServiceConfig'])
        should_be_fsid = cfg['ceph']['rbd_secret_uuid']
        if should_be_fsid == "CHANGEME":
            cfg['ceph']['rbd_secret_uuid'] = get_fsid()
            str_config = StringIO()
            cfg.write(str_config)
            str_config.seek(0)
            data['spec']['cinder']['template']['cinderVolumes']['ceph']['customServiceConfig'] =\
                str_config.read()
    except:
        pass
    return data


sections = split_sections(args.src)
for section in sections:
    data = yaml.safe_load(''.join(section))
    if data['kind'] == 'OpenStackControlPlane':
        data = work_around_missing_fsid(data)
        with open(args.dst, 'w') as dst_yaml_file:
            yaml.dump(data, dst_yaml_file, indent=2)
        break
