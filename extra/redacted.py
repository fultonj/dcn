#!/usr/bin/env python3
# copy a tree of multi doc yaml files but with passwords redacted

import os
import shutil
import sys
import yaml


SRC='dcn_src'
DST='dcn'
SECRETS = ['ceph-conf-files',
           'dataplane-ansible-ssh-private-key-secret',
           'nova-migration-ssh-key',
           'osp-secret'
           ]


def delete_contents(directory_path):
    # Check if the directory exists
    if os.path.exists(directory_path):
        # Iterate over the contents of the directory
        for root, dirs, files in os.walk(directory_path, topdown=False):
            # Delete files
            for file in files:
                file_path = os.path.join(root, file)
                try:
                    os.remove(file_path)
                except OSError as e:
                    print(f"Error: {file_path} : {e.strerror}")
            # Delete subdirectories
            for dir_name in dirs:
                dir_path = os.path.join(root, dir_name)
                try:
                    os.rmdir(dir_path)
                except OSError as e:
                    print(f"Error: {dir_path} : {e.strerror}")


def create_or_reset_directory(directory_path):
    # Delete contents of the directory
    delete_contents(directory_path)

    if os.path.exists(directory_path):
        # If it exists, delete it
        try:
            os.rmdir(directory_path)
        except OSError as e:
            print(f"Error: {directory_path} : {e.strerror}")
    # Create a new directory
    try:
        os.mkdir(directory_path)
    except OSError as e:
        print(f"Error: {directory_path} : {e.strerror}")


def list_files(directory):
    # return list of absolute paths to yaml files in directory
    paths = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.yaml') or file.endswith('.yml'):
                paths.append(os.path.join(root, file))
    return paths


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

# main
create_or_reset_directory(DST)
files = list_files(SRC)
for f in files:
    sections = split_sections(f)
    new_path = f.replace(SRC, DST)
    os.makedirs(os.path.dirname(new_path), exist_ok=True)
    with open(new_path, 'w') as f:
        for section in sections:
            data = yaml.safe_load(''.join(section))
            f.write('---\n')
            if data['kind'] != 'Secret':
                # copy the file directly if it's not a secret
                f.write(''.join(section))
            else:
                # if we're working on one of the secrets
                if data['metadata']['name'] in SECRETS:
                    # then maintain all keys, but redact values
                    for k, v in data['data'].items():
                        data['data'][k] = '<redacted>'
                # write out the modified data as yaml
                f.write(yaml.safe_dump(data, default_flow_style=False, indent=2))
