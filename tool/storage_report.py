"""What is actually filling Supabase Storage — READ ONLY.

    python tool/storage_report.py

Lists every bucket, every object in it, and what each weighs, biggest first.
It deletes nothing and it cannot: the anon key it uses has no rights beyond
what the buckets' policies already grant a visitor.

── Why a report before a broom ──
"Storage is full" is a symptom with several possible causes — one huge asset,
a thousand small ones, or orphans from an upload path that changed. The fix is
different for each, and deleting from a bucket is not undoable. Measure first.

The project ref and anon key come from lib/core/supabase/supabase_client.dart,
so this cannot drift from what the app itself talks to.
"""
import json
import pathlib
import re
import urllib.error
import urllib.request

DART = pathlib.Path('lib/core/supabase/supabase_client.dart')
src = DART.read_text(encoding='utf-8')
URL = re.search(r"supabaseUrl = '([^']+)'", src).group(1)
KEY = re.search(r"supabaseAnonKey =\s*'([^']+)'", src, re.S).group(1)


def post(path, body):
    req = urllib.request.Request(
        f'{URL}{path}',
        data=json.dumps(body).encode(),
        headers={
            'apikey': KEY,
            'Authorization': f'Bearer {KEY}',
            'Content-Type': 'application/json',
        },
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def get(path):
    req = urllib.request.Request(
        f'{URL}{path}',
        headers={'apikey': KEY, 'Authorization': f'Bearer {KEY}'},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def main():
    try:
        buckets = get('/storage/v1/bucket')
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors='replace')[:300]
        print(f'could not list buckets: HTTP {e.code}\n  {body}')
        print('\nIf this says the project is restricted, storage is already '
              'over quota and the API is switched off — the clean-up has to '
              'happen in the Supabase dashboard, not from here.')
        return

    grand = 0
    for b in buckets:
        name = b['id']
        total, rows = 0, []
        for offset in range(0, 10000, 100):
            page = post(f'/storage/v1/object/list/{name}', {
                'prefix': '', 'limit': 100, 'offset': offset,
                'sortBy': {'column': 'name', 'order': 'asc'},
            })
            if not page:
                break
            for o in page:
                size = ((o.get('metadata') or {}).get('size') or 0)
                total += size
                rows.append((size, o['name']))
        grand += total
        pub = 'public' if b.get('public') else 'private'
        print(f'\n=== {name}  ({pub})  {len(rows)} objects  '
              f'{total / 1024 / 1024:.1f} MB ===')
        for size, n in sorted(rows, reverse=True)[:12]:
            print(f'  {size // 1024:7d} KB  {n}')
        if len(rows) > 12:
            print(f'  … and {len(rows) - 12} more')
    print(f'\nTOTAL {grand / 1024 / 1024:.1f} MB across {len(buckets)} buckets')


main()
