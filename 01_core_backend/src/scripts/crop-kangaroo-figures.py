# -*- coding: utf-8 -*-
"""
classify-kangaroo-figures.py (formerly crop-kangaroo-figures.py)

Classifies each Math Kangaroo question image as HAS_FIGURE or NO_FIGURE.
  - HAS_FIGURE: image contains a meaningful visual element → keep original image
  - NO_FIGURE: image is just rendered text + answer choices → clear figure_data
    so iOS falls back to showing the parsed text instead

Cost: ~1747 questions x ~$0.0005 = ~$1 (gpt-4o-mini, low-detail vision)
Time: ~10 minutes with concurrency=8

Reads OPENAI_API_KEY2 from .env (falls back to OPENAI_API_KEY).

Usage:
  DATABASE_URL=postgresql://... \\
  python3 src/scripts/crop-kangaroo-figures.py --dry-run --limit 10 --save-samples /tmp/k

  DATABASE_URL=postgresql://... \\
  python3 src/scripts/crop-kangaroo-figures.py
"""

import argparse
import base64
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
parser = argparse.ArgumentParser()
parser.add_argument('--limit',       type=int, default=0,    help='Max rows to process (0 = all)')
parser.add_argument('--concurrency', type=int, default=8,    help='Parallel vision API calls')
parser.add_argument('--dry-run',     action='store_true',    help='No DB writes; save samples for inspection')
parser.add_argument('--force',       action='store_true',    help='Re-classify already-processed images')
parser.add_argument('--save-samples', type=str, default=None, help='Save samples to this directory')
args = parser.parse_args()

# ---------------------------------------------------------------------------
# Load .env (manual parser, no dotenv dependency)
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
loaded     = load_env_file(env_path)
print(f'[env] Loaded {loaded} vars from {env_path}' if loaded else f'[env] {env_path} not found')

# ---------------------------------------------------------------------------
# Imports & client setup
# ---------------------------------------------------------------------------
try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
    from openai import OpenAI
except ImportError as e:
    print(f'ERROR: missing dependency: {e.name}')
    print('Run: pip3 install psycopg2-binary openai')
    sys.exit(1)

api_key = os.environ.get('OPENAI_API_KEY2') or os.environ.get('OPENAI_API_KEY')
if not api_key:
    print('ERROR: neither OPENAI_API_KEY2 nor OPENAI_API_KEY is set')
    sys.exit(1)
key_label = 'OPENAI_API_KEY2' if os.environ.get('OPENAI_API_KEY2') else 'OPENAI_API_KEY'
print(f'[env] Using {key_label} (prefix: {api_key[:8]}…)')

if not os.environ.get('DATABASE_URL'):
    print('ERROR: DATABASE_URL not set')
    sys.exit(1)

client = OpenAI(api_key=api_key)
DB_URL = os.environ['DATABASE_URL']

# ---------------------------------------------------------------------------
# Vision prompt — classify HAS_FIGURE vs NO_FIGURE
# ---------------------------------------------------------------------------
VISION_PROMPT = """This image is from a Math Kangaroo competition problem. It contains
question text and answer choices. Sometimes it ALSO contains a meaningful
visual element (a table of numbers, a geometric shape, a diagram, a clock,
a grid, a picture, etc.) that is REQUIRED to understand or answer the question.

Decide:
  - "HAS_FIGURE" — the image contains a non-text visual element that
    a student NEEDS to see in order to solve the problem.
  - "NO_FIGURE" — the image is essentially just rendered question text
    plus the A-E answer choices. Even if there are decorative borders or
    formatting, if the question can be fully understood from the text alone,
    answer NO_FIGURE.

Reply with ONLY one word: HAS_FIGURE or NO_FIGURE."""

# ---------------------------------------------------------------------------
# Schema migration
# ---------------------------------------------------------------------------
def ensure_schema(conn):
    with conn.cursor() as cur:
        cur.execute("""
            ALTER TABLE question_bank
            ADD COLUMN IF NOT EXISTS figure_cropped BOOLEAN NOT NULL DEFAULT false;
        """)
        conn.commit()

# ---------------------------------------------------------------------------
# Classify one image
# ---------------------------------------------------------------------------
def classify_image(image_b64, mime='image/jpeg'):
    try:
        resp = client.chat.completions.create(
            model='gpt-4o-mini',
            max_tokens=10,
            temperature=0,
            messages=[{
                'role': 'user',
                'content': [
                    {'type': 'text', 'text': VISION_PROMPT},
                    {'type': 'image_url', 'image_url': {
                        'url': f'data:{mime};base64,{image_b64}',
                        'detail': 'low',
                    }},
                ],
            }],
        )
        text = resp.choices[0].message.content.strip().upper()
        if 'HAS_FIGURE' in text:
            return 'HAS_FIGURE'
        if 'NO_FIGURE' in text:
            return 'NO_FIGURE'
        return None
    except Exception:
        return None

def process_one(row):
    qid     = row['id']
    fig_b64 = row['figure_data']
    mime    = (row['figure_mime'] or 'image/jpeg')
    if not fig_b64:
        return {'id': qid, 'status': 'skip_no_data'}
    cls = classify_image(fig_b64, mime)
    if cls == 'HAS_FIGURE':
        return {'id': qid, 'status': 'has_figure'}
    if cls == 'NO_FIGURE':
        return {'id': qid, 'status': 'no_figure'}
    return {'id': qid, 'status': 'vision_failed'}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print(f'\nKangaroo figure classifier')
    print(f'Concurrency : {args.concurrency}')
    print(f'Limit       : {args.limit or "all"}')
    print(f'Dry run     : {args.dry_run}')
    print(f'Force       : {args.force}\n')

    conn = psycopg2.connect(DB_URL, sslmode='require' if 'rlwy.net' in DB_URL or 'railway' in DB_URL else 'prefer')
    ensure_schema(conn)

    where = "source = 'kangaroo' AND figure_data IS NOT NULL"
    if not args.force:
        where += " AND figure_cropped = false"

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(f"SELECT COUNT(*) AS n FROM question_bank WHERE {where}")
        total_avail = cur.fetchone()['n']
        cur.execute(f"""
            SELECT id, figure_data, figure_mime
            FROM question_bank
            WHERE {where}
            ORDER BY id
            LIMIT %s
        """, (args.limit if args.limit else total_avail,))
        rows = cur.fetchall()

    print(f'Rows to process: {len(rows)} (of {total_avail} available)\n')
    if not rows:
        print('Nothing to do.')
        return

    if args.save_samples:
        os.makedirs(args.save_samples, exist_ok=True)

    stats = {'has_figure': 0, 'no_figure': 0, 'vision_failed': 0, 'skip_no_data': 0}
    samples_saved = 0
    t0 = time.time()

    with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = {executor.submit(process_one, row): row for row in rows}
        done = 0
        for fut in as_completed(futures):
            row    = futures[fut]
            result = fut.result()
            stats[result['status']] = stats.get(result['status'], 0) + 1
            done += 1

            if args.save_samples and samples_saved < 10:
                path = os.path.join(args.save_samples, f"{result['status']}_{row['id']}.jpg")
                with open(path, 'wb') as f:
                    f.write(base64.b64decode(row['figure_data']))
                samples_saved += 1
            if args.dry_run and done <= 10:
                print(f"  [{row['id'][:8]}] {result['status']}")

            if not args.dry_run and result['status'] in ('has_figure', 'no_figure'):
                try:
                    with conn.cursor() as cur:
                        if result['status'] == 'no_figure':
                            # Clear figure_data so iOS falls back to parsed text
                            cur.execute("""
                                UPDATE question_bank
                                SET figure_data = NULL, figure_mime = NULL, figure_cropped = true
                                WHERE id = %s
                            """, (row['id'],))
                        else:  # has_figure: keep image, mark processed
                            cur.execute("""
                                UPDATE question_bank SET figure_cropped = true WHERE id = %s
                            """, (row['id'],))
                        conn.commit()
                except Exception as e:
                    print(f"\n  DB update failed for {row['id']}: {e}")
                    conn.rollback()

            if done % 50 == 0 or done == len(rows):
                rate = done / (time.time() - t0)
                eta  = (len(rows) - done) / rate if rate > 0 else 0
                msg  = (f"  {done}/{len(rows)}  "
                        f"has_fig={stats['has_figure']}  "
                        f"no_fig={stats['no_figure']}  "
                        f"failed={stats.get('vision_failed', 0)}  "
                        f"rate={rate:.1f}/s  eta={int(eta)}s")
                print(msg, end='\r' if done < len(rows) else '\n', flush=True)

    print(f"\n\nDone in {int(time.time() - t0)}s")
    print(f"  HAS figure (kept)     : {stats['has_figure']}")
    print(f"  NO figure (cleared)   : {stats['no_figure']}")
    print(f"  Vision failed         : {stats.get('vision_failed', 0)}")
    print(f"  No data               : {stats.get('skip_no_data', 0)}")

    if args.save_samples:
        print(f"\n  Samples in {args.save_samples}/ — prefix is the classification")

    conn.close()

if __name__ == '__main__':
    main()
