#!/usr/bin/env python3
"""Compare two dictionary (or verse) dumps ("$$$key" then text; mod2imp / dictdump layout), ignoring white space
and the case of keys.  Prints "<label>: n of m entries identical".
   cmpdict.py <reference> <other> <label> [nospace] [minimum identical]
nospace: all blanks are ignored (not only their amount); with a minimum the exit status is 0 when that many agree."""
import sys, re
def load(f):
    t = open(f, encoding='utf-8', errors='replace').read()
    return [(k.strip(), re.sub(r'\s+', ' ', b).strip()) for k, _, b in (e.partition('\n') for e in t.split('$$$')[1:])]
nospace = 'nospace' in sys.argv[4:]
nums = [x for x in sys.argv[4:] if x.isdigit()]
a, b = load(sys.argv[1]), load(sys.argv[2])
if nospace:
    a = [(k, v.replace(' ', '')) for k, v in a]
    b = [(k, v.replace(' ', '')) for k, v in b]
d = {k.upper(): v for k, v in b}
same = sum(1 for k, v in a if d.get(k.upper()) == v)
print(f"{sys.argv[3]}: {same} of {len(a)} entries identical ({len(b)} in the other)")
sys.exit(0 if same >= (int(nums[0]) if nums else len(a)) else 1)
