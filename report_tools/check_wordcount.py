import re
import sys
from docx import Document

d = Document(sys.argv[1])
limits = {
    "摘  要": 800, "1.1": 400, "1.2": 400, "1.3": 400, "1.4": 200,
    "1.5": 200, "1.6": 200, "4.1": 300, "4.2": 1000,
}
cur = None
counts = {}
for p in d.paragraphs:
    t = p.text.strip()
    if not t:
        continue
    m = re.match(r"^(\d\.\d|摘\s+要|第[一二三四五]部分)\s", t)
    if m:
        key = t.split()[0]
        cur = key
        counts.setdefault(cur, [0, []])
        continue
    if cur:
        counts.setdefault(cur, [0, []])
        counts[cur][0] += len(t)

print("%-10s %6s %8s" % ("节", "字数", "限制"))
total_ok = True
for k, (n, _) in sorted(counts.items()):
    lim = limits.get(k.replace("　", " ").strip(), None)
    mark = ""
    if lim is not None:
        mark = "OK" if n <= lim else "!!超"
        if n > lim:
            total_ok = False
    print("%-10s %6d %8s %s" % (k, n, lim if lim is not None else "-", mark))
print("ALL_WITHIN_LIMITS:", total_ok)

full = "\n".join(p.text for p in d.paragraphs)
for kw in ["学校", "大学", "学院", "中科亿海微"]:
    hits = [p.text[:60] for p in d.paragraphs if kw in p.text]
    print("kw %s -> %d  %s" % (kw, len(hits), hits[0] if hits else ""))
