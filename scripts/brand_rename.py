#!/usr/bin/env python3
"""
brand_rename.py — in-place Readest→阅易 rebrand for the packaged frontend.

Two passes:
  1) JS chunks: replace `Readest` ONLY inside string literals ('...', "...",
     `...` template text). Code identifiers (isReadestCloudEnabled), lowercase
     urls/ids and ALL_CAPS constants are untouched — a naive sed breaks the
     bundle. Template interpolations ${...} are skipped (identifiers inside).
  2) Locale files: rename KEYS containing Readest to the patched form so the
     renamed in-code keys still resolve ("About Readest"→"About 阅易").
Also rewrites manifest.json fields and html/txt payloads (plain replace).

Every patched .js is syntax-checked with `node --check`; on failure the file
is restored untouched and reported.
"""
import io
import json
import os
import subprocess
import sys

BRAND = '\u9605\u6613'  # 阅易
OLD = 'Readest'
FRONTEND = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'frontend')
FRONTEND = os.path.normpath(FRONTEND)

# a quote opens a string only after one of these (minified-js heuristic to
# avoid misparsing regex literals like /["']/)
OPENERS = set('=(,:[!&|?{;+<>*-')
KEYWORDS = {'return', 'case', 'typeof', 'new', 'delete', 'void', 'throw',
            'in', 'of', 'do', 'else', 'await', 'yield', 'instanceof'}


def _after_keyword(out) -> bool:
    # scan back over the emitted text for [a-zA-Z]+ boundary == keyword
    # (only invoked when prev significant char is a letter, so cost is bounded)
    buf = ''.join(out)[-12:]
    word = ''
    for ch in reversed(buf):
        if ch.isalpha():
            word = ch + word
        else:
            break
    return word in KEYWORDS


def patch_js_source(s: str):
    out = []
    changed = 0
    i, n = 0, len(s)
    stack = []  # ['q', char] | ['tpl', brace_depth]
    prev_sig = ''  # last significant (non-space) char emitted, for opener heuristic

    def replaceable() -> bool:
        if not stack:
            return False
        top = stack[-1]
        return top[0] == 'q' or (top[0] == 'tpl' and top[1] == 0)

    while i < n:
        c = s[i]
        if replaceable():
            if s.startswith(OLD, i):
                out.append(BRAND)
                changed += 1
                i += len(OLD)
                prev_sig = BRAND[-1]
                continue
            if c == '\\':
                out.append(s[i:i + 2])
                i += 2
                continue
            top = stack[-1]
            if top[0] == 'q':
                if c == top[1]:
                    stack.pop()
                out.append(c)
                prev_sig = c
                i += 1
                continue
            # template text at depth 0
            if c == '`':
                stack.pop()
                out.append(c)
                prev_sig = c
                i += 1
                continue
            if c == '$' and i + 1 < n and s[i + 1] == '{':
                top[1] = 1
                out.append('${')
                i += 2
                continue
            out.append(c)
            prev_sig = c
            i += 1
            continue
        # code region
        kw = prev_sig.isalpha() and _after_keyword(out)
        if c in ('"', "'") and (prev_sig == '' or prev_sig in OPENERS or kw):
            stack.append(['q', c])
            out.append(c)
            prev_sig = c
            i += 1
            continue
        if c == '`' and (prev_sig == '' or prev_sig in OPENERS or kw):
            stack.append(['tpl', 0])
            out.append(c)
            prev_sig = c
            i += 1
            continue
        if stack and stack[-1][0] == 'tpl':
            top = stack[-1]
            if top[1] > 0:
                if c == '{':
                    top[1] += 1
                elif c == '}':
                    top[1] -= 1
                out.append(c)
                prev_sig = c
                i += 1
                continue
            # unmatched (should not happen at depth 0 in code region)
            out.append(c)
            prev_sig = c
            i += 1
            continue
        out.append(c)
        if not c.isspace():
            prev_sig = c
        i += 1
    return ''.join(out), changed


def patch_chunks():
    total = 0
    failures = []
    root = os.path.join(FRONTEND, '_next', 'static', 'chunks')
    for name in sorted(os.listdir(root)):
        if not name.endswith('.js'):
            continue
        p = os.path.join(root, name)
        s = io.open(p, encoding='utf-8').read()
        if OLD not in s:
            continue
        patched, changed = patch_js_source(s)
        if changed == 0:
            continue
        io.open(p, 'w', encoding='utf-8').write(patched)
        # syntax gate: revert on any parse failure
        r = subprocess.run(['node', '--check', p], capture_output=True, text=True)
        if r.returncode != 0:
            io.open(p, 'w', encoding='utf-8').write(s)
            failures.append((name, r.stderr.strip().splitlines()[-1] if r.stderr else 'parse error'))
            print(f'  REVERTED {name}: {failures[-1][1]}')
        else:
            total += changed
            print(f'  patched {name}: {changed} strings')
    return total, failures


def patch_locales():
    root = os.path.join(FRONTEND, 'locales')
    renamed = 0
    for lang in sorted(os.listdir(root)):
        p = os.path.join(root, lang, 'translation.json')
        if not os.path.isfile(p):
            continue
        try:
            d = json.load(io.open(p, encoding='utf-8'))
        except Exception as e:
            print(f'  SKIP {lang}: {e}')
            continue
        nd = {}
        for k, v in d.items():
            nk = k.replace(OLD, BRAND) if OLD in k else k
            if nk != k:
                renamed += 1
            nd[nk] = v
        io.open(p, 'w', encoding='utf-8').write(
            json.dumps(nd, ensure_ascii=False, indent=2))
    print(f'  locale keys renamed: {renamed}')


def patch_manifest_and_payloads():
    # manifest.json
    p = os.path.join(FRONTEND, 'manifest.json')
    if os.path.isfile(p):
        try:
            m = json.load(io.open(p, encoding='utf-8'))
            for f in ('name', 'short_name', 'description'):
                if f in m and isinstance(m[f], str):
                    m[f] = m[f].replace(OLD, BRAND)
            io.open(p, 'w', encoding='utf-8').write(
                json.dumps(m, ensure_ascii=False, indent=2))
            print('  manifest.json patched')
        except Exception as e:
            print(f'  manifest SKIP: {e}')
    # html + RSC txt payloads: plain case-sensitive replace
    for sub in ('',):
        base = FRONTEND
        for name in sorted(os.listdir(base)):
            fp = os.path.join(base, name)
            if not os.path.isfile(fp):
                continue
            if name.endswith('.html') or name.endswith('.txt'):
                s = io.open(fp, encoding='utf-8', errors='ignore').read()
                if OLD in s:
                    io.open(fp, 'w', encoding='utf-8').write(s.replace(OLD, BRAND))
                    print(f'  payload patched: {name}')


def main():
    print('[brand_rename] JS chunks:')
    total, failures = patch_chunks()
    print(f'  total strings rebranded: {total}')
    print('[brand_rename] locales:')
    patch_locales()
    print('[brand_rename] manifest/payloads:')
    patch_manifest_and_payloads()
    if failures:
        print(f'FAILURES: {len(failures)} chunks reverted (see above)')
        sys.exit(1)
    print('[brand_rename] DONE')


if __name__ == '__main__':
    main()
