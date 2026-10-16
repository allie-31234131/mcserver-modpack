"""Fetch only pinned compile-time APIs. Does not install any gameplay mods."""
from pathlib import Path
import hashlib
import json
import urllib.request

root = Path(__file__).resolve().parent
destination = root / 'neoforge/local-deps'
destination.mkdir(parents=True, exist_ok=True)
for item in json.loads((root / 'neoforge-dependencies.lock.json').read_text(encoding='utf-8')):
    name = item['file']
    if Path(name).name != name or not name.endswith('.jar'):
        raise ValueError('Invalid dependency filename')
    path = destination / name
    if path.exists() and hashlib.sha512(path.read_bytes()).hexdigest() == item['sha512']:
        continue
    request = urllib.request.Request(item['url'], headers={'User-Agent': 'MCServer-YSM-development-build/1'})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    if hashlib.sha512(data).hexdigest() != item['sha512']:
        raise ValueError('Dependency hash mismatch: ' + name)
    path.write_bytes(data)
    print('Verified compile-time API:', name)
