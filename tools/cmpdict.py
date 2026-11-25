#!/usr/bin/env python3
"""Compare two dictionary dumps ("$$$key" then text; mod2imp / dictdump layout), ignoring white space
and the case of keys.  Prints "<label>: n of m entries identical".   cmpdict.py <reference> <other> <label>"""
import sys, re
def load(f):
    t = open(f, encoding='utf-8', errors='replace').read()
    return [(k.strip(), re.sub(r'\s+', ' ', b).strip()) for k, _, b in (e.partition('\n') for e in t.split('$$$')[1:])]
a, b = load(sys.argv[1]), load(sys.argv[2])
d = {k.upper(): v for k, v in b}
same = sum(1 for k, v in a if d.get(k.upper()) == v)
print(f"{sys.argv[3]}: {same} of {len(a)} entries identical ({len(b)} in the other)")
sys.exit(0 if same == len(a) else 1)
