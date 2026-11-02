#!/usr/bin/env python3
"""Lists every tr("…") key used in the Kotlin/Swift sources (and checks i18n/strings.json covers them).

  extract.py           print keys missing from strings.json (exit 1 if any)
  extract.py --all     print all keys
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert import scan  # noqa: E402

def keys():
    out = set()
    files = glob.glob(f'{ROOT}/ios/**/*.swift', recursive=True) + glob.glob(f'{ROOT}/android/*/src/main/**/*.kt', recursive=True)
    for f in files:
        if '/build/' in f or '/.build/' in f: continue
        src = open(f, encoding='utf-8').read()
        kotlin = f.endswith('.kt')
        for m in re.finditer(r'\btr\(', src):
            q = m.end()
            while q < len(src) and src[q] in ' \n': q += 1
            if q >= len(src) or src[q] != '"': continue
            for s, e, parts, exprs in scan(src[q:], kotlin):
                if exprs: print(f'warning: interpolation inside tr() key in {f}', file=sys.stderr)
                k = parts[0].replace('\\$', '$').replace('\\n', '\n').replace('\\"', '"')
                out.add(k)
                break
    return out

if __name__ == '__main__':
    ks = keys()
    if '--all' in sys.argv:
        for k in sorted(ks): print(json.dumps(k, ensure_ascii=False))
        sys.exit(0)
    table = json.load(open(f'{ROOT}/i18n/strings.json', encoding='utf-8'))
    missing = sorted(k for k in ks if k not in table)
    for k in missing: print('missing:', json.dumps(k, ensure_ascii=False))
    bad = []
    for k, v in table.items():
        forms = v.values() if isinstance(v, dict) else [v]
        for f in forms:
            if sorted(re.findall(r'\{\d\}|%[.0-9]*[sdf]', f)) != sorted(re.findall(r'\{\d\}|%[.0-9]*[sdf]', k)):
                bad.append(k)
    for k in bad: print('placeholder mismatch:', json.dumps(k, ensure_ascii=False))
    missing += bad
    unused = sorted(k for k in table if k not in ks and not k.startswith('web.'))
    for k in unused: print('unused:', json.dumps(k, ensure_ascii=False), file=sys.stderr)
    print(f'{len(ks)} keys, {len(missing)} missing', file=sys.stderr)
    for copy in ['android/brushcore/src/main/resources/i18n/en.json', 'ios/BrushCore/Sources/BrushCore/Resources/en.json']:
        path = f'{ROOT}/{copy}'
        if os.path.exists(path) and json.load(open(path, encoding='utf-8')) != table:
            print(f'out of date: {copy} (run i18n/sync.sh)'); missing.append(copy)
    sys.exit(1 if missing else 0)
