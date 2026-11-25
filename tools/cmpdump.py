#!/usr/bin/env python3
"""Compare build/bibdump output with Sword's mod2imp for a module.
Usage: cmpdump.py <mod2imp-name> <bibdump-arg>"""
import subprocess, sys, re
CANON = set(re.findall(r'\{"([^"]+)", "[^"]*", "[^"]*", \d+\}', open('private-samples/sword-master/include/canon.h').read()))
def parse(txt, canon_only=False):
    out = []
    for ent in txt.split('$$$')[1:]:
        key, _, body = ent.partition('\n')
        if re.search(r'\d+:\d+$', key.strip()) and not key.strip().endswith(':0') and ' 0:' not in key:
            body = body.rstrip('\n').rstrip()
            if body.strip() and (not canon_only or key.strip().rsplit(' ', 1)[0] in CANON):
                out.append((key.strip(), body.strip()))
    return out
a = subprocess.run(['mod2imp', sys.argv[1]], capture_output=True, text=True, errors='replace').stdout
b = subprocess.run(['build/bibdump', sys.argv[2]], capture_output=True, text=True, errors='replace').stdout
A, B = parse(a, True), parse(b)
bad = [(x, y) for x, y in zip(A, B) if x[1] != y[1]]
print(f"{sys.argv[1]}: sword={len(A)} mine={len(B)} mismatches={len(bad)}")
for x, y in bad[:3]:
    print('  S:', x[0], x[1][:100]); print('  M:', y[0], y[1][:100])
