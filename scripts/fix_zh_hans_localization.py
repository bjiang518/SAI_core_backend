#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fix_zh_hans_localization.py

Detects and fixes Traditional Chinese words/characters mixed into
the Simplified Chinese (zh-Hans) localization file, using GPT.

Usage:
    export OPENAI_API_KEY=sk-...
    python fix_zh_hans_localization.py [--dry-run]

Options:
    --dry-run   Show proposed changes without writing to disk.
"""

import os
import sys
import re
import json
import copy
import argparse
from openai import OpenAI

# ── Config ──────────────────────────────────────────────────────────────────

INPUT_FILE  = "../02_ios_app/StudyAI/zh-Hans.lproj/Localizable.strings"
OUTPUT_FILE = INPUT_FILE          # overwrite in-place (backup is written first)
BACKUP_FILE = INPUT_FILE + ".bak"
BATCH_SIZE  = 40                  # lines per GPT call (values only, not comments/blanks)
MODEL       = "gpt-4o-mini"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_PATH  = os.path.normpath(os.path.join(SCRIPT_DIR, INPUT_FILE))
OUTPUT_PATH = os.path.normpath(os.path.join(SCRIPT_DIR, OUTPUT_FILE))
BACKUP_PATH = os.path.normpath(os.path.join(SCRIPT_DIR, BACKUP_FILE))

# ── Helpers ──────────────────────────────────────────────────────────────────

def parse_strings_file(path: str) -> list[dict]:
    """
    Parse a .strings file into a list of line objects:
      { "type": "entry",   "key": "...", "value": "...", "raw": "..." }
      { "type": "comment", "raw": "..." }
      { "type": "blank",   "raw": "" }
    """
    lines = []
    # Regex: "key" = "value";   (handles escaped quotes inside)
    entry_re = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')

    with open(path, encoding="utf-8") as f:
        for raw_line in f:
            raw = raw_line.rstrip("\n")
            stripped = raw.strip()
            if not stripped:
                lines.append({"type": "blank", "raw": raw})
            elif stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
                lines.append({"type": "comment", "raw": raw})
            else:
                m = entry_re.match(stripped)
                if m:
                    lines.append({
                        "type":  "entry",
                        "key":   m.group(1),
                        "value": m.group(2),
                        "raw":   raw,
                    })
                else:
                    # Preserve unrecognised lines as-is
                    lines.append({"type": "other", "raw": raw})
    return lines


def build_prompt(entries: list[dict]) -> str:
    """Build the GPT prompt for a batch of key-value entries."""
    kv_block = "\n".join(
        f'{i}: "{e["key"]}" = "{e["value"]}"'
        for i, e in enumerate(entries)
    )
    return f"""You are a Simplified Chinese (zh-Hans) localization proofreader for an iOS education app called StudyAI.

Your ONLY task is to replace Traditional Chinese characters or words with their Simplified Chinese equivalents.
This is a CHARACTER/WORD SUBSTITUTION task — NOT a translation or rewriting task.

## Hard rules

1. ONLY fix Traditional Chinese script. Do not change anything else.
2. Keep the EXACT same meaning, sentence structure, and wording as the original.
   - If the original says "资料库" (meaning the app's Library feature), keep "资料库" — do NOT change it to "数据库".
   - If a word is already Simplified Chinese, leave it untouched even if you think a "better" word exists.
3. Do NOT rephrase, paraphrase, simplify, or improve the text in any way.
4. Do NOT change: English words, numbers, punctuation, format specifiers (%@, %d, %1$@, \\n, \\t, \\\\).
   CRITICAL: Preserve ALL escape sequences EXACTLY as-is. \\n must remain \\n (two characters: backslash + n).
   Never convert \\n into an actual newline character in your JSON output.
5. Do NOT change the key names.
6. If a value is already entirely Simplified Chinese, omit it from the result.
7. CRITICAL: If you are not 100% certain a character or word is Traditional Chinese, do NOT change it.
   When in doubt, omit the entry. False positives are worse than false negatives here.

## What counts as Traditional Chinese (fix these)

Characters with Traditional-only forms, e.g.:
  銷 → 销   銷售 撤銷       繁 → 繁 (same stroke — ignore)
  設 → 设   設定 設置       帳 → 账   帳戶
  應 → 应   應用程式       夥 → 伙   夥伴
  協 → 协   協助           聯 → 联   聯絡 聯繫
  援 (支援) → 支持          儲 → 储   儲存 → 保存
  視窗 → 窗口              歡迎 → 欢迎
  點擊 → 点击              請 → 请

Words that are Traditional phrasing even if characters look similar:
  登入 → 登录       設定 → 设置       應用程式 → 应用程序
  聯絡 → 联系       支援 → 支持       協助 → 帮助
  撤銷 → 撤销       確認 → 确认       顯示 → 显示

## What NOT to change (app-specific terminology — keep as-is)

  资料库   (= the in-app Library tab, NOT a database)
  数据     (already Simplified)
  Any term that is already standard Simplified Chinese

## App context

This is a student-facing iOS app. Strings are short UI labels and messages.
The key name gives context (e.g., "tab.library", "settings.title", "proMode.revertGrading").

## Entries to review

{kv_block}

## Response format

Return ONLY a valid JSON object mapping the string index to the corrected value.
Include ONLY entries that need changes. If nothing needs changing, return {{}}.

Example: {{"0": "corrected value", "3": "another corrected value"}}
"""


def _count_format_specifiers(s: str) -> dict:
    """Count %@ %d %1$@ etc. and \\n occurrences in a value string."""
    return {
        "percent_at":  s.count("%@"),
        "percent_d":   s.count("%d"),
        "newline":     s.count("\\n"),
        "positional":  len(re.findall(r"%\d+\$@", s)),
        "real_newline": s.count("\n"),  # actual newline — should be 0
    }


def _validate_correction(original: str, corrected: str, key: str) -> tuple[bool, str]:
    """
    Return (is_valid, reason).
    Rejects corrections that:
      - introduce actual newline characters (GPT unescaped \\n)
      - change the count of format specifiers
      - are identical to the original (no-op)
    """
    if corrected == original:
        return False, "identical to original"

    if "\n" in corrected and "\n" not in original:
        return False, "introduced real newline (GPT unescaped \\\\n)"

    orig_counts = _count_format_specifiers(original)
    new_counts  = _count_format_specifiers(corrected)
    for spec in ("percent_at", "percent_d", "newline", "positional"):
        if orig_counts[spec] != new_counts[spec]:
            return False, f"format specifier mismatch: {spec} {orig_counts[spec]} → {new_counts[spec]}"

    return True, "ok"


def fix_batch(client: OpenAI, entries: list[dict]) -> dict[int, str]:
    """Call GPT for a batch; return {{index: corrected_value}} dict."""
    prompt = build_prompt(entries)
    response = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": prompt}],
        temperature=0,
        response_format={"type": "json_object"},
    )
    raw = response.choices[0].message.content.strip()
    try:
        result = json.loads(raw)
        corrections = {int(k): v for k, v in result.items()}
    except json.JSONDecodeError as e:
        print(f"  [WARN] JSON parse error: {e}")
        print(f"  Raw response: {raw[:300]}")
        return {}

    # Validate each correction before returning
    validated = {}
    for idx, new_value in corrections.items():
        if idx >= len(entries):
            print(f"  [WARN] index {idx} out of range, skipping.")
            continue
        original = entries[idx]["value"]
        key      = entries[idx]["key"]
        ok, reason = _validate_correction(original, new_value, key)
        if ok:
            validated[idx] = new_value
        else:
            print(f"  [SKIP] [{key}] rejected — {reason}")
            print(f"         orig: {original[:80]}")
            print(f"         gpt:  {new_value[:80]}")
    return validated


def render_entry(key: str, value: str) -> str:
    """Re-render a key/value pair as a .strings line."""
    return f'"{key}" = "{value}";'


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="Print proposed changes without writing files.")
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        sys.exit("ERROR: OPENAI_API_KEY environment variable not set.")

    client = OpenAI(api_key=api_key)

    print(f"Reading: {INPUT_PATH}")
    lines = parse_strings_file(INPUT_PATH)

    # Collect entry indices for batching
    entry_indices = [i for i, l in enumerate(lines) if l["type"] == "entry"]
    total_entries = len(entry_indices)
    print(f"Found {total_entries} translation entries across {len(lines)} lines.")

    # Work on a mutable copy
    updated_lines = copy.deepcopy(lines)
    total_changes = 0

    # Process in batches
    for batch_start in range(0, total_entries, BATCH_SIZE):
        batch_idxs = entry_indices[batch_start : batch_start + BATCH_SIZE]
        batch_entries = [lines[i] for i in batch_idxs]
        batch_num = batch_start // BATCH_SIZE + 1
        total_batches = (total_entries + BATCH_SIZE - 1) // BATCH_SIZE
        print(f"\nBatch {batch_num}/{total_batches} ({len(batch_entries)} entries)...", end=" ", flush=True)

        corrections = fix_batch(client, batch_entries)

        if not corrections:
            print("no changes.")
            continue

        print(f"{len(corrections)} fix(es):")
        for local_idx, new_value in sorted(corrections.items()):
            line_idx  = batch_idxs[local_idx]
            old_value = lines[line_idx]["value"]
            key       = lines[line_idx]["key"]

            print(f'  [{key}]')
            print(f'    繁: {old_value}')
            print(f'    简: {new_value}')

            if not args.dry_run:
                updated_lines[line_idx]["value"] = new_value
                updated_lines[line_idx]["raw"]   = render_entry(key, new_value)
            total_changes += 1

    print(f"\n{'─'*60}")
    print(f"Total changes: {total_changes}")

    if args.dry_run:
        print("Dry-run mode — no files written.")
        return

    if total_changes == 0:
        print("Nothing to write.")
        return

    # Backup original
    import shutil
    shutil.copy2(INPUT_PATH, BACKUP_PATH)
    print(f"Backup saved: {BACKUP_PATH}")

    # Write updated file
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        for line in updated_lines:
            f.write(line["raw"] + "\n")
    print(f"Updated file written: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
