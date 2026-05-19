# -*- coding: utf-8 -*-
"""
Extract Math Kangaroo English problems from qualcomm/M3Kang (Parquet)
and write to kangaroo_en.jsonl for the Node.js importer.

Requires:
  pip3 install datasets pillow

Usage:
  python3 src/scripts/extract-kangaroo-data.py
  python3 src/scripts/extract-kangaroo-data.py --split standard
  python3 src/scripts/extract-kangaroo-data.py --limit 200 --dry-run

Output:
  kangaroo_en.jsonl  - one JSON object per line:
    { id, level, text, label, image_b64 (or null), year }
"""

import argparse
import base64
import io
import json
import os
import sys

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
parser = argparse.ArgumentParser()
parser.add_argument('--split',    default='high_quality',
                    choices=['high_quality', 'standard'],
                    help='Which M3Kang split to extract (default: high_quality)')
parser.add_argument('--limit',    type=int, default=0,
                    help='Max English rows to extract (0 = all)')
parser.add_argument('--dry-run',  action='store_true',
                    help='Print first 3 rows, do not write file')
parser.add_argument('--schema',   action='store_true',
                    help='Dump first 3 raw rows with no filtering to inspect field names/values')
parser.add_argument('--out',      default='kangaroo_en.jsonl',
                    help='Output file path')
args = parser.parse_args()

# ---------------------------------------------------------------------------
# Imports (after args so --help works without deps)
# ---------------------------------------------------------------------------
try:
    from datasets import load_dataset
except ImportError:
    print('ERROR: datasets not installed.  Run:  pip install datasets pillow')
    sys.exit(1)

HF_TOKEN = os.environ.get('HF_TOKEN')
if not HF_TOKEN:
    print('WARNING: HF_TOKEN not set.  Set it in your shell:')
    print('  export HF_TOKEN=hf_xxxx')

# ---------------------------------------------------------------------------
# Extract year from problem ID (e.g. "2023-L5-P1" → "2023")
# ---------------------------------------------------------------------------
def extract_year(problem_id: str) -> str:
    if not problem_id:
        return ''
    parts = str(problem_id).split('-')
    if parts and parts[0].isdigit() and len(parts[0]) == 4:
        return parts[0]
    return ''

# ---------------------------------------------------------------------------
# Convert PIL Image → base64 PNG string (None if no image)
# ---------------------------------------------------------------------------
def image_to_b64(img):
    # type: (object) -> object
    if img is None:
        return None
    try:
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        return base64.b64encode(buf.getvalue()).decode('utf-8')
    except Exception:
        return None

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
print(f'\nM3Kang extraction  split={args.split}  limit={args.limit or "all"}  dry={args.dry_run}  schema={args.schema}')
print('Loading dataset (streaming)…\n')

ds = load_dataset(
    'qualcomm/M3Kang',
    split=args.split,
    streaming=True,
    token=HF_TOKEN,
    trust_remote_code=False,
)

# --schema: dump raw rows without any filtering
if args.schema:
    import sys
    print('Raw field dump (first 5 rows, no filtering):\n')
    for i, row in enumerate(ds):
        if i >= 5:
            break
        print('--- Row %d ---' % i)
        for k, v in row.items():
            if k == 'image' and v is not None:
                display = '<image: %s>' % type(v).__name__
            else:
                display = repr(v)[:120]
            print('  %-18s: %s' % (k, display))
        print()
    print('Unique language values in first 200 rows:')
    ds2 = load_dataset('qualcomm/M3Kang', split=args.split, streaming=True, token=HF_TOKEN, trust_remote_code=False)
    langs = {}
    for i, row in enumerate(ds2):
        if i >= 200:
            break
        lang = str(row.get('language', row.get('lang', '?')))
        langs[lang] = langs.get(lang, 0) + 1
    for lang, cnt in sorted(langs.items(), key=lambda x: -x[1])[:15]:
        print('  %-20s : %d' % (lang, cnt))
    sys.exit(0)

count      = 0
skipped    = 0
with_image = 0

out_file = open(args.out, 'w', encoding='utf-8') if not args.dry_run else None

try:
    for row in ds:
        # high_quality split is all English — no language filter needed.
        # standard split has 108 languages; filter to 'eng'.
        if args.split == 'standard':
            lang = (row.get('language') or '').lower().strip()
            if lang not in ('en', 'eng', 'english'):
                skipped += 1
                continue

        text       = row.get('text') or row.get('question') or ''
        label      = (row.get('label') or row.get('answer') or row.get('correct_answer') or 'A').strip().upper()
        level      = row.get('level')          # numeric: 0=Pre-Ecolier … 5=Student
        if level is None:
            level  = row.get('grade_level') or 0
        text_only  = bool(row.get('text_only', False))
        pid        = row.get('id') or row.get('problem_id') or ('row%d' % count)
        img        = row.get('image')

        img_b64 = image_to_b64(img)
        if img_b64:
            with_image += 1

        record = {
            'id':        str(pid),
            'level':     int(level) if str(level).isdigit() else level,
            'text':      text,
            'label':     label,
            'year':      extract_year(str(pid)),
            'text_only': text_only,
            'image_b64': img_b64,
        }

        if args.dry_run:
            if count < 3:
                print(f'--- Row {count + 1} ---')
                print(f'  id     : {record["id"]}')
                print(f'  level  : {record["level"]}')
                print(f'  label  : {record["label"]}')
                print(f'  image  : {"yes (" + str(len(img_b64)) + " chars)" if img_b64 else "no"}')
                print(f'  text   : {text[:200]}')
                print()
        else:
            out_file.write(json.dumps(record, ensure_ascii=False) + '\n')

        count += 1
        if count % 50 == 0:
            print(f'\r  {count} English rows extracted…', end='', flush=True)

        if args.limit and count >= args.limit:
            break

finally:
    if out_file:
        out_file.close()

print(f'\n\nDone.')
print(f'  English rows : {count}')
print(f'  With images  : {with_image}')
print(f'  Non-English  : {skipped}')
if not args.dry_run:
    size_kb = os.path.getsize(args.out) // 1024
    print(f'  Output file  : {args.out}  ({size_kb} KB)')
    print(f'\nNext step:')
    print(f'  node src/scripts/import-kangaroo.js --from-file={args.out}')
