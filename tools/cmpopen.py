#!/usr/bin/env python3
"""Check one of this project's readers for an XML Bible format against an independent extraction of the
file (a few lines of Python, no code shared with the reader):

   cmpopen.py zefania|osis|usfx <file> <our dump> <label> [minimum identical]

<our dump> is `bibdump <file> -p` (the "$$$Book c:v" layout).  Prints "label: n of m verses identical"
and exits 1 when fewer than the minimum agree (default: all)."""
import re, sys, html, xml.etree.ElementTree as ET
OSIS = "Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr Ezra Neh Esth Job Ps Prov Eccl Song Isa Jer Lam Ezek Dan Hos Joel Amos Obad Jonah Mic Nah Hab Zeph Hag Zech Mal Matt Mark Luke John Acts Rom 1Cor 2Cor Gal Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Phlm Heb Jas 1Pet 2Pet 1John 2John 3John Jude Rev".split()
USFX = "GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM EZK DAN HOS JOL AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP COL 1TH 2TH 1TI 2TI TIT PHM HEB JAS 1PE 2PE 1JN 2JN 3JN JUD REV".split()

def norm(s):
    s = html.unescape(re.sub(r'<[^>]+>', '', s)).replace('¶', '')
    return re.sub(r'\s+', ' ', s).strip()

def load_zefania(p):
    r = ET.parse(p).getroot(); out = {}
    for b in r.iter('BIBLEBOOK'):
        bn = int(b.get('bnumber'))
        for c in b.iter('CHAPTER'):
            for v in c.iter('VERS'):
                out[(bn, int(c.get('cnumber')), int(v.get('vnumber')))] = norm(''.join(v.itertext()))
    return out

def load_osis(p):
    t = open(p, encoding='utf-8').read(); out = {}
    t = re.sub(r'<note\b.*?</note>', '', t, flags=re.S)
    for m in re.finditer(r'<verse osisID="([^"]+)" sID="([^"]+)"[^>]*/>(.*?)<verse eID="\2"\s*/>', t, flags=re.S):
        b, c, v = m.group(1).split('.')[:3]
        if b in OSIS:
            out[(OSIS.index(b) + 1, int(c), int(v))] = norm(m.group(3))
    return out

def load_usfx(p):
    t = open(p, encoding='utf-8').read(); out = {}
    for bm in re.finditer(r'<book id="([^"]+)">(.*?)</book>', t, flags=re.S):
        if bm.group(1) not in USFX:
            continue
        bn = USFX.index(bm.group(1)) + 1; ch = 0; title = ''
        for m in re.finditer(r'<c id="(\d+)"\s*/>|<d\b[^>]*>(.*?)</d>|<v id="(\d+)"[^>]*/>(.*?)<ve\s*/>', bm.group(2), flags=re.S):
            if m.group(1):
                ch = int(m.group(1)); title = ''
            elif m.group(2) is not None:
                title = norm(m.group(2)) + ' '          # a psalm title: text of the verse that follows
            else:
                x = re.sub(r'<f\b.*?</f>|<x\b.*?</x>|<fig\b.*?</fig>|<s\b.*?</s>', '', m.group(4), flags=re.S)
                out[(bn, ch, int(m.group(3)))] = title + norm(x)
                title = ''
    return out

def load_dump(p):
    d = {}; order = []
    for e in open(p, encoding='utf-8', errors='replace').read().split('$$$')[1:]:
        k, _, b = e.partition('\n')
        m = re.match(r'(\S+) (\d+):(\d+)', k.strip())
        if m:
            if m.group(1) not in order: order.append(m.group(1))
            d[(m.group(1), int(m.group(2)), int(m.group(3)))] = re.sub(r'\s+', ' ', b).strip()
    return {(order.index(k[0]) + 1, k[1], k[2]): v for k, v in d.items() if k[0] in order[:66]}

kind, f, dump, label = sys.argv[1:5]
theirs = {'zefania': load_zefania, 'osis': load_osis, 'usfx': load_usfx}[kind](f)
mine = load_dump(dump)
common = [k for k in theirs if k in mine]
same = sum(1 for k in common if theirs[k] == mine[k])
need = int(sys.argv[5]) if len(sys.argv) > 5 else len(theirs)
print(f"{label}: {same} of {len(theirs)} verses identical ({len(mine)} read)")
sys.exit(0 if same >= need else 1)
