#!/usr/bin/env python3
"""Paired-SIMULATOR smoke test. Inserts an explicitly synthetic test note in the Watch outbox.
Never use against a physical device or a production store. Leaves its labelled note for inspection.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--phone', required=True, help='Booted paired iPhone simulator UDID')
parser.add_argument('--watch', required=True, help='Booted Watch simulator UDID')
args = parser.parse_args()
os.environ.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')

def sim(*values, check=True):
    return subprocess.run(['xcrun', 'simctl', *values], check=check, capture_output=True, text=True)

def container(device, bundle):
    return Path(sim('get_app_container', device, bundle, 'data').stdout.strip())

phone = container(args.phone, 'com.distyll.wrist')
watch = container(args.watch, 'com.distyll.wrist.watchkitapp')
sim('terminate', args.watch, 'com.distyll.wrist.watchkitapp', check=False)
outbox = watch / 'Documents/pending-captures.json'
outbox.parent.mkdir(parents=True, exist_ok=True)
items = json.loads(outbox.read_text()) if outbox.exists() else []
id = str(uuid.uuid4()).upper()
epoch = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
items.append({'id': id, 'createdAt': (datetime.datetime.now(datetime.timezone.utc) - epoch).total_seconds(),
              'duration': 0, 'text': 'SIMULATOR TEST: Remember to water the orchid tomorrow.'})
temp = outbox.with_suffix('.tmp')
temp.write_text(json.dumps(items))
temp.replace(outbox)
sim('launch', args.phone, 'com.distyll.wrist')
sim('launch', args.watch, 'com.distyll.wrist.watchkitapp')
archive = phone / 'Documents/memos.json'
for _ in range(45):
    state = json.loads(archive.read_text()) if archive.exists() else {}
    rows = state if isinstance(state, list) else state.get('memos', [])
    matches = [m for m in rows if m['id'] == id]
    pending = json.loads(outbox.read_text())
    if len(matches) == 1 and not any(m['id'] == id for m in pending):
        print('PASS: synthetic Watch note persisted once on iPhone and application ACK cleared Watch outbox.')
        print('Capture ID:', id)
        break
    time.sleep(2)
else:
    raise SystemExit('FAIL: no verified iPhone save + Watch ACK within 90s. Paired simulator transport may be unavailable.')
