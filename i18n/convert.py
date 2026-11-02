#!/usr/bin/env python3
"""Wraps Hungarian UI string literals in tr("…", args) calls (Kotlin and Swift).

Interpolations become numbered placeholders:
  Kotlin  "Ma $n/${g.perDay}"  ->  tr("Ma {0}/{1}", n, g.perDay)
  Swift   "Ma \(n)/\(g.perDay)" -> tr("Ma {0}/{1}", n, g.perDay)
Usage: convert.py [--write] [--list] files...
Literals are translated when they contain a Hungarian letter or are in EXTRA (below).
"""
import json, re, sys

HU = re.compile(r'[áéíóöőúüűÁÉÍÓÖŐÚÜŰ]')
EXTRA = set(json.load(open(__file__.rsplit('/', 1)[0] + '/extra_keys.json'))) if __import__('os').path.exists(__file__.rsplit('/', 1)[0] + '/extra_keys.json') else set()


def scan(src, kotlin):
    """Yields (start, end, parts, exprs) for each plain double-quoted string literal (not raw/multiline)."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            i = src.find('\n', i)
            if i < 0: return
            continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        if kotlin and c == "'":
            # char literal
            j = i + 1
            while j < n and src[j] != "'":
                j += 2 if src[j] == '\\' else 1
            i = j + 1
            continue
        if src.startswith('"""', i):
            j = src.find('"""', i + 3)
            i = n if j < 0 else j + 3
            continue
        if c == '#' and not kotlin and src.startswith('#"', i):
            j = src.find('"#', i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            start = i
            i += 1
            parts, exprs, buf = [], [], []
            while i < n and src[i] != '"':
                if src[i] == '\n':
                    break
                if src[i] == '\\' and not (not kotlin and src.startswith('\\(', i)):
                    buf.append(src[i:i + 2]); i += 2; continue
                if kotlin and src[i] == '$' and i + 1 < n and (src[i + 1] == '{' or src[i + 1].isalpha() or src[i + 1] == '_'):
                    if src[i + 1] == '{':
                        j = match(src, i + 2, '{', '}', kotlin)
                        exprs.append(src[i + 2:j]); i = j + 1
                    else:
                        m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', src[i + 1:])
                        exprs.append(m.group(0)); i += 1 + len(m.end() * 'x')
                    parts.append(''.join(buf)); buf = []
                    continue
                if not kotlin and src.startswith('\\(', i):
                    j = match(src, i + 2, '(', ')', kotlin)
                    exprs.append(src[i + 2:j]); i = j + 1
                    parts.append(''.join(buf)); buf = []
                    continue
                buf.append(src[i]); i += 1
            parts.append(''.join(buf))
            end = i + 1
            yield start, end, parts, exprs
            i = end
            continue
        i += 1


def match(src, i, open_c, close_c, kotlin):
    depth = 1
    while i < len(src):
        c = src[i]
        if c == '"':
            # nested string literal inside an interpolation
            for s, e, _, _ in scan(src[i:], kotlin):
                i += e
                break
            continue
        if c == open_c: depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0: return i
        i += 1
    raise ValueError('unbalanced interpolation')


def key_of(parts):
    out = parts[0]
    for k, p in enumerate(parts[1:]):
        out += '{%d}' % k + p
    return out


def translatable(key):
    return bool(HU.search(key)) or key in EXTRA


def convert(src, kotlin):
    out, last, keys = [], 0, []
    for s, e, parts, exprs in scan(src, kotlin):
        key = key_of(parts)
        if not translatable(key):
            continue
        before = src[max(0, s - 3):s]
        if before.endswith('tr(') :
            continue
        keys.append(key)
        lit = '"' + key.replace('$', '\\$' if kotlin else '$') + '"' if kotlin else '"' + key + '"'
        args = ''.join(', ' + x.strip() for x in exprs)
        out.append(src[last:s]); out.append(f'tr({lit}{args})'); last = e
    out.append(src[last:])
    return ''.join(out), keys


if __name__ == '__main__':
    write = '--write' in sys.argv
    listing = '--list' in sys.argv
    allkeys = []
    for f in [a for a in sys.argv[1:] if not a.startswith('--')]:
        src = open(f).read()
        new, keys = convert(src, f.endswith('.kt'))
        allkeys += keys
        if write and new != src:
            open(f, 'w').write(new)
    if listing:
        for k in sorted(set(allkeys)): print(k)
    print(f'{len(allkeys)} literals, {len(set(allkeys))} unique', file=sys.stderr)
