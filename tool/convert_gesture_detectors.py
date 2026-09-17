#!/usr/bin/env python3
"""Replace GestureDetector(...) call sites with Pressable(...) wherever the
call only uses params Pressable also supports (onTap, onLongPress, behavior,
child, key) -- so a drag/pan/scale/double-tap GestureDetector elsewhere in
the app is left alone rather than silently losing that gesture.

Usage: python3 tool/convert_gesture_detectors.py [--dry-run] [path ...]
Paths default to everything under lib/. Prints one line per file changed,
and a final "skipped (other gestures)" list for call sites it deliberately
left alone.
"""
import argparse
import os
import re
import sys

ALLOWED_PARAMS = {'onTap', 'onLongPress', 'behavior', 'child', 'key'}
PRESSABLE_IMPORT_SUFFIX = 'core/ui/pressable.dart'


def find_matching_paren(text, open_idx):
    """[open_idx] is the index of an opening '(' -- returns the index of its
    matching ')', skipping over nested brackets, string literals and
    comments."""
    depth = 0
    i = open_idx
    n = len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            nl = text.find('\n', i)
            i = nl if nl != -1 else n
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            end = text.find('*/', i + 2)
            i = (end + 2) if end != -1 else n
            continue
        if c in ('"', "'"):
            quote = c
            triple = text[i:i + 3] == quote * 3
            j = i + (3 if triple else 1)
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if triple and text[j:j + 3] == quote * 3:
                    j += 3
                    break
                if not triple and text[j] == quote:
                    j += 1
                    break
                j += 1
            i = j
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def top_level_param_names(args_text):
    """Names of the top-level named parameters in a call's argument text
    (the bit between the outer parens), ignoring nested calls/collections
    and string contents."""
    names = []
    depth = 0
    i = 0
    n = len(args_text)
    seg_start = 0

    def flush(seg):
        seg = seg.strip()
        if not seg:
            return
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:', seg)
        if m:
            names.append(m.group(1))
        else:
            names.append(None)  # positional or unparsed -- caller aborts

    while i < n:
        c = args_text[i]
        if c == '/' and i + 1 < n and args_text[i + 1] == '/':
            nl = args_text.find('\n', i)
            i = nl if nl != -1 else n
            continue
        if c == '/' and i + 1 < n and args_text[i + 1] == '*':
            end = args_text.find('*/', i + 2)
            i = (end + 2) if end != -1 else n
            continue
        if c in ('"', "'"):
            quote = c
            triple = args_text[i:i + 3] == quote * 3
            j = i + (3 if triple else 1)
            while j < n:
                if args_text[j] == '\\':
                    j += 2
                    continue
                if triple and args_text[j:j + 3] == quote * 3:
                    j += 3
                    break
                if not triple and args_text[j] == quote:
                    j += 1
                    break
                j += 1
            i = j
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            flush(args_text[seg_start:i])
            seg_start = i + 1
        i += 1
    flush(args_text[seg_start:i])
    return names


def relative_import(from_file, lib_root):
    depth = os.path.dirname(os.path.relpath(from_file, lib_root)).count(os.sep)
    up = '../' * (depth + 1) if depth >= 0 else ''
    # from_file is lib/X/Y/Z.dart -> relpath dirname is X/Y -> depth=1 -> '../../'
    d = os.path.relpath(from_file, lib_root)
    parts = d.split(os.sep)
    ups = len(parts) - 1
    return ('../' * ups) + PRESSABLE_IMPORT_SUFFIX if ups > 0 else PRESSABLE_IMPORT_SUFFIX


def process_file(path, lib_root, dry_run):
    with open(path, encoding='utf-8') as f:
        text = f.read()

    occurrences = []
    skipped = 0
    idx = 0
    while True:
        idx = text.find('GestureDetector(', idx)
        if idx == -1:
            break
        open_paren = idx + len('GestureDetector')
        close_paren = find_matching_paren(text, open_paren)
        if close_paren == -1:
            idx += 1
            continue
        args_text = text[open_paren + 1:close_paren]
        names = top_level_param_names(args_text)
        # 'child' required: Pressable's is a required param (it wraps the
        # child to animate it), unlike GestureDetector's -- a bare full-
        # screen dismiss barrier ("GestureDetector(onTap: x)", no child) is
        # valid there and must be left alone, not "converted" into a
        # compile error.
        if (names and all(n in ALLOWED_PARAMS for n in names)
                and 'onTap' in names and 'child' in names):
            occurrences.append(idx)
        else:
            skipped += 1
        idx = close_paren + 1

    if not occurrences:
        return 0, skipped

    # Replace right-to-left so earlier offsets stay valid.
    new_text = text
    for start in reversed(occurrences):
        new_text = (
            new_text[:start]
            + 'Pressable('
            + new_text[start + len('GestureDetector('):]
        )

    if 'core/ui/pressable.dart' not in new_text:
        import_path = relative_import(path, lib_root)
        # Insert after the last existing import line (or after the last
        # `library;`/leading comment block if there are no imports at all --
        # every file touched here already imports material.dart, so this
        # always finds at least one).
        lines = new_text.split('\n')
        last_import = -1
        for i, line in enumerate(lines):
            if line.startswith('import '):
                last_import = i
        if last_import == -1:
            print(f'  ! {path}: no import line found, import NOT added -- fix by hand')
        else:
            lines.insert(last_import + 1, f"import '{import_path}';")
            new_text = '\n'.join(lines)

    if not dry_run:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(new_text)
    return len(occurrences), skipped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('paths', nargs='*', default=['lib'])
    args = ap.parse_args()

    lib_root = 'lib'
    total_changed = 0
    total_skipped = 0
    files_changed = 0
    for root_path in args.paths:
        for dirpath, _, filenames in os.walk(root_path):
            for fn in filenames:
                if not fn.endswith('.dart'):
                    continue
                full = os.path.join(dirpath, fn)
                if full.endswith('pressable.dart'):
                    continue
                changed, skipped = process_file(full, lib_root, args.dry_run)
                total_skipped += skipped
                if changed:
                    files_changed += 1
                    total_changed += changed
                    print(f'{full}: converted {changed}, skipped {skipped} (other gestures)')

    print(f'\n{files_changed} files changed, {total_changed} GestureDetector(s) '
          f'-> Pressable, {total_skipped} left alone (use gestures Pressable '
          f"doesn't support)")


if __name__ == '__main__':
    main()
