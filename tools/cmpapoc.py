#!/usr/bin/env python3
"""Compare ALL verses incl. Apocrypha of build/bibdump -a with mod2imp (order independent).
Usage: cmpapoc.py <mod2imp-name> <bibdump-arg>"""
import subprocess, sys, re
from collections import Counter
def parse(txt):
    out = []
    for ent in txt.split('$$$')[1:]:
        key, _, body = ent.partition('\n')
        if re.search(r'\d+:[1-9]\d*$', key.strip()):
            body = body.rstrip('\n').rstrip().strip()
            if body: out.append(body)
    return out
a = subprocess.run(['mod2imp', sys.argv[1]], capture_output=True, text=True, errors='replace').stdout
b = subprocess.run(['build/bibdump', sys.argv[2], '-a'], capture_output=True, text=True, errors='replace').stdout
A, B = Counter(parse(a)), Counter(parse(b))
print(f"{sys.argv[1]}: sword={sum(A.values())} mine={sum(B.values())} only-sword={sum((A-B).values())} only-mine={sum((B-A).values())}")
