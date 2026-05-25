# -*- coding: utf-8 -*-
"""
restore-kangaroo-figures.py

Restores Math Kangaroo figure_data from the local kangaroo_en.jsonl file
(produced by extract-kangaroo-data.py). Only touches rows where the
current figure_data is non-NULL (i.e. HAS_FIGURE classifications) —
leaves the cleared NO_FIGURE rows alone.

Matches by source_id:
  DB:    kangaroo_lvl-0_2015_1
  JSONL: lvl-0_2015_1

Usage:
  DATABASE_URL=postgresql://... \\
  python3 src/scripts/restore-kangaroo-figures.py --dry-run

  DATABASE_URL=postgresql://... \\
  python3 src/scripts/restore-kangaroo-figures.py
"""

import argparse
import base64
import io
import json
import os
import sys
import time

# ---------------------------------------------------------------------------
parser = argparse.ArgumentParser()
parser.add_argument('--jsonl',   default='kangaroo_en.jsonl', help='Path to source JSONL')
parser.add_argument('--dry-run', action='store_true', help='Report only, no DB writes')
parser.add_argument('--limit',   type=int, default=0, help='Max rows to process (0 = all)')
parser.add_argument('--force-all', action='store_true',
                    help='Restore ALL kangaroo rows including NULL (e.g. to undo NO_FIGURE clearing)')
args = parser.parse_args()

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
def load_env_file(path):
    if not os.path.exists(path):
        return 0
    n = 0
    with open(path, 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, _, val = line.partition('=')
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = val
                n += 1
    return n

script_dir = os.path.dirname(os.path.abspath(__file__))
env_path   = os.path.abspath(os.path.join(script_dir, '..', '..', '.env'))
load_env_file(env_path)

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
    from PIL import Image
except ImportError as e:
    print(f'ERROR: missing dependency: {e.name}')
    print('Run: pip3 install psycopg2-binary pillow')
    sys.exit(1)

if not os.environ.get('DATABASE_URL'):
    print('ERROR: DATABASE_URL not set')
    sys.exit(1)

DB_URL = os.environ['DATABASE_URL']
JSONL  = args.jsonl

if not os.path.exists(JSONL):
    print(f'ERROR: {JSONL} not found. Run extract-kangaroo-data.py first.')
    sys.exit(1)

# ---------------------------------------------------------------------------
# Load JSONL into a dict: source_id_suffix → image_b64
# ---------------------------------------------------------------------------
print(f'Reading {JSONL}…')
jsonl_map = {}
with open(JSONL, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if obj.get('image_b64') and obj.get('id'):
                jsonl_map[obj['id']] = obj['image_b64']
        except Exception:
            continue
print(f'  Loaded {len(jsonl_map)} images from JSONL')

# ---------------------------------------------------------------------------
# Fetch kangaroo rows from DB
# ---------------------------------------------------------------------------
conn = psycopg2.connect(DB_URL, sslmode='require' if 'rlwy.net' in DB_URL or 'railway' in DB_URL else 'prefer')

where = "source = 'kangaroo'"
if not args.force_all:
    where += " AND figure_data IS NOT NULL"

with conn.cursor(cursor_factory=RealDictCursor) as cur:
    cur.execute(f"""
        SELECT id, source_id, figure_data
        FROM question_bank
        WHERE {where}
        ORDER BY id
        {f'LIMIT {args.limit}' if args.limit else ''}
    """)
    rows = cur.fetchall()
print(f'Rows to check: {len(rows)}')

# ---------------------------------------------------------------------------
# Compare and restore
# ---------------------------------------------------------------------------
def img_dims_from_b64(b64):
    try:
        img = Image.open(io.BytesIO(base64.b64decode(b64)))
        return img.size
    except Exception:
        return None

restored = 0
already_full = 0
no_match = 0
t0 = time.time()

for i, row in enumerate(rows):
    src_id  = row['source_id']  # "kangaroo_lvl-0_2015_1"
    jsonl_id = src_id.replace('kangaroo_', '') if src_id and src_id.startswith('kangaroo_') else src_id

    original_b64 = jsonl_map.get(jsonl_id)
    if not original_b64:
        no_match += 1
        continue

    current_dims  = img_dims_from_b64(row['figure_data']) if row['figure_data'] else None
    original_dims = img_dims_from_b64(original_b64)

    # If current image is already the original size, skip
    if current_dims and original_dims and current_dims == original_dims:
        already_full += 1
        continue

    if args.dry_run:
        print(f"  [{src_id}] current={current_dims} → original={original_dims}  WOULD RESTORE")
    else:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE question_bank
                    SET figure_data = %s, figure_mime = 'image/jpeg'
                    WHERE id = %s
                """, (original_b64, row['id']))
                conn.commit()
        except Exception as e:
            print(f"  DB update failed for {row['id']}: {e}")
            conn.rollback()
            continue
    restored += 1

    if (i + 1) % 100 == 0:
        rate = (i + 1) / (time.time() - t0)
        print(f"  {i+1}/{len(rows)}  restored={restored}  rate={rate:.1f}/s")

print(f"\nDone in {int(time.time() - t0)}s")
print(f"  Restored      : {restored}")
print(f"  Already full  : {already_full}  (image already matches original size)")
print(f"  No JSONL match: {no_match}  (source_id not in JSONL)")
conn.close()
