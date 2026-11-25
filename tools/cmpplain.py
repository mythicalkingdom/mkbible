#!/usr/bin/env python3
"""Compare my plain text (bibdump -p) with Sword's own plain rendering (diatheke -f plain).
Usage: cmpplain.py <diatheke module name> <bibdump arg> [SWORD_PATH]"""
import subprocess, sys, re, os
mod, arg = sys.argv[1], sys.argv[2]
env = dict(os.environ)
if len(sys.argv) > 3: env['SWORD_PATH'] = sys.argv[3]
mine = {}
cur = None
for line in subprocess.run(['build/bibdump', arg, '-p'], capture_output=True, text=True, errors='replace').stdout.split('\n'):
    if line.startswith('$$$'): cur = line[3:]
    elif cur: mine[cur] = line; cur = None
books = re.findall(r'^Gen|^Exod|^Lev|^Num|^Deut', '')  # unused
names = ["Genesis","Exodus","Leviticus","Numbers","Deuteronomy","Joshua","Judges","Ruth","1 Samuel","2 Samuel","1 Kings","2 Kings","1 Chronicles","2 Chronicles","Ezra","Nehemiah","Esther","Job","Psalms","Proverbs","Ecclesiastes","Song of Solomon","Isaiah","Jeremiah","Lamentations","Ezekiel","Daniel","Hosea","Joel","Amos","Obadiah","Jonah","Micah","Nahum","Habakkuk","Zephaniah","Haggai","Zechariah","Malachi","Matthew","Mark","Luke","John","Acts","Romans","1 Corinthians","2 Corinthians","Galatians","Ephesians","Philippians","Colossians","1 Thessalonians","2 Thessalonians","1 Timothy","2 Timothy","Titus","Philemon","Hebrews","James","1 Peter","2 Peter","1 John","2 John","3 John","Jude","Revelation of John"]
osis = ["Gen","Exod","Lev","Num","Deut","Josh","Judg","Ruth","1Sam","2Sam","1Kgs","2Kgs","1Chr","2Chr","Ezra","Neh","Esth","Job","Ps","Prov","Eccl","Song","Isa","Jer","Lam","Ezek","Dan","Hos","Joel","Amos","Obad","Jonah","Mic","Nah","Hab","Zeph","Hag","Zech","Mal","Matt","Mark","Luke","John","Acts","Rom","1Cor","2Cor","Gal","Eph","Phil","Col","1Thess","2Thess","1Tim","2Tim","Titus","Phlm","Heb","Jas","1Pet","2Pet","1John","2John","3John","Jude","Rev"]
def norm(t): return re.sub(r'\s+', ' ', t).strip()
def nosw(t): return re.sub(r' ?\[[^\]]*\]', '', t)
same = diff = missing = spacing = 0
shown = 0
for n, o in zip(names, osis):
    out = subprocess.run(['diatheke', '-b', mod, '-f', 'plain', '-k', n], capture_output=True, text=True, errors='replace', env=env).stdout
    # entries look like "Genesis 1:1: text"; continuation lines belong to the previous verse
    ents = re.split(r'(?m)^(?=[1-3A-Z][A-Za-z ]+ \d+:\d+: )', out)
    for e in ents:
        m = re.match(r'([1-3A-Z][A-Za-z ]+) (\d+):(\d+): (.*)', e, re.S)
        if not m: continue
        key = f"{o} {m.group(2)}:{m.group(3)}"
        text = re.sub(r'\n\([^)\n]*\)\s*$', '', m.group(4))   # trailing "(module)" line
        if key not in mine: missing += 1; continue
        a, b = norm(nosw(text)), norm(mine[key])
        if a == b: same += 1
        elif re.sub(r'\s', '', a) == re.sub(r'\s', '', b): spacing += 1   # only blanks differ (e.g. a note between two words)
        else:
            diff += 1
            if shown < 4:
                shown += 1
                print(f"DIFF {key}\n  sword: {a[:160]}\n  mine : {b[:160]}")
print(f"{mod}: identical {same}, only blanks differ {spacing}, different {diff}, not in my dump {missing}")
