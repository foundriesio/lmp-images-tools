#!/usr/bin/python3
#
# Copyright (c) 2019 Foundries.io
# SPDX-License-Identifier: BSD-3-Clause
#
import argparse
import hashlib
import json
import os
import sys

from datetime import datetime
from zipfile import ZipFile

import requests


def get_token(oauth_server, client, secret):
    data = {'grant_type': 'client_credentials'}
    url = oauth_server
    if url[-1] != '/':
        url += '/'
    url += 'token'
    r = requests.post(url, data=data, auth=(client, secret))
    r.raise_for_status()
    return r.json()['access_token']


def add_target(targets_json, app, version, content):
    with open(args.targets_json) as f:
        data = json.load(f)

    now = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    content = content.encode()
    m = hashlib.sha256()
    m.update(content)
    data['targets'][app + '-' + version] = {
        'hashes': {'sha256': m.hexdigest()},
        'length': len(content),
        'custom': {
            'targetFormat': 'BINARY',
            'version': version,
            'name': app,
            'hardwareIds': ['all'],
            'createdAt': now,
            'updatedAt': now,
        },
    }
    with open(args.targets_json, 'w') as f:
        json.dump(data, f, indent=2)


def publish(args):
    with ZipFile(args.credentials) as zf:
        with zf.open('tufrepo.url') as f:
            repourl = f.read().strip().decode()

        with zf.open('treehub.json') as f:
            oauth2 = json.load(f).get('oauth2')

    if repourl[-1] != '/':
        repourl += '/'

    token = ''
    if oauth2:
        token = get_token(
            oauth2['server'], oauth2['client_id'], oauth2['client_secret'])

    app = os.path.basename(args.dockerapp.name)
    url = repourl + 'api/v1/user_repo/targets/' + app + '-' + args.version
    r = requests.put(url,
                     params={'name': app, 'version': args.version},
                     files={'file': ('filename', args.dockerapp)},
                     headers={'Authorization': 'Bearer ' + token})
    if r.status_code == 412:
        print('OTA reposerver has offline keys, using: ' + args.targets_json)
        os.lseek(args.dockerapp.fileno(), 0, 0)
        add_target(args.targets_json, app, args.version, args.dockerapp.read())
    elif r.status_code != 200:
        sys.exit('Unable to create %s: HTTP_%d\n%s' % (
            url, r.status_code, r.text))


def merge(args):
    with open(args.targets_json) as f:
        data = json.load(f)

    targets = data['targets']
    filename = os.path.basename(args.dockerapp) + '-' + args.version
    app = filename[:filename.find('.dockerapp-')]
    assert filename in targets, '%s not in targets' % filename

    img = targets[args.ostree_branch + '-' + args.version]
    img['custom'].setdefault('docker_apps', {})[app] = {'filename': filename}

    with open(args.targets_json, 'w') as f:
        json.dump(data, f, indent=2)


def get_args():
    parser = argparse.ArgumentParser(
        'Manage dockerapps on the OTA Connect reposerver')

    cmds = parser.add_subparsers(title='Commands')

    p = cmds.add_parser('publish')
    p.set_defaults(func=publish)
    p.add_argument('dockerapp', type=argparse.FileType('r'))
    p.add_argument('credentials', type=argparse.FileType('rb'))
    p.add_argument('version')
    p.add_argument('targets_json')

    p = cmds.add_parser('merge')
    p.set_defaults(func=merge)
    p.add_argument('targets_json')
    p.add_argument('dockerapp')
    p.add_argument('version')
    p.add_argument('ostree_branch')

    return parser.parse_args()


if __name__ == '__main__':
    args = get_args()
    if getattr(args, 'func', None):
        args.func(args)
