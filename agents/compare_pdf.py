#!/usr/bin/env python3
"""
compare_pdf.py -- compare the *content* of two PDFs (D13 vs D2010 render of the
same report over the same gbak-identical DB).

PDF bytes are never identical across engines: FastReport stamps a /CreationDate,
a producer string, and usually a "vytištěno / tisk dne <datetime>" line, plus
object ordering differs. So we compare normalized *text*:

  - extract text per page (pypdf)
  - strip volatile tokens: explicit print timestamps, bare dates/times, the
    PDF has no run-stamp in body for most, but headers carry "dd.mm.yyyy hh:mm"
  - collapse whitespace
  - compare page count + per-page normalized text

Exit/JSON: pages_a, pages_b, identical (bool), first_diff (page, a_excerpt,
b_excerpt). Usage: compare_pdf.py a.pdf b.pdf [--json out.json]
"""
import sys, re, json, argparse
from pypdf import PdfReader

# dd.mm.yyyy  or dd. mm. yyyy, optional time hh:mm(:ss)
DATE = re.compile(r'\b\d{1,2}\.\s?\d{1,2}\.\s?\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?')
TIME = re.compile(r'\b\d{1,2}:\d{2}(?::\d{2})?\b')
WS   = re.compile(r'\s+')

def norm(t: str) -> str:
    t = DATE.sub('<DATE>', t)
    t = TIME.sub('<TIME>', t)
    t = WS.sub(' ', t)
    return t.strip()

def pages(path):
    r = PdfReader(path)
    return [norm(p.extract_text() or '') for p in r.pages]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('a'); ap.add_argument('b'); ap.add_argument('--json')
    a = ap.parse_args()
    pa, pb = pages(a.a), pages(a.b)
    res = {'a': a.a, 'b': a.b, 'pages_a': len(pa), 'pages_b': len(pb),
           'identical': False, 'first_diff': None, 'chars_a': sum(len(x) for x in pa),
           'chars_b': sum(len(x) for x in pb)}
    if len(pa) == len(pb) and all(x == y for x, y in zip(pa, pb)):
        res['identical'] = True
    else:
        n = min(len(pa), len(pb))
        for i in range(n):
            if pa[i] != pb[i]:
                # locate first differing char window
                j = next((k for k in range(min(len(pa[i]), len(pb[i]))) if pa[i][k] != pb[i][k]), 0)
                res['first_diff'] = {'page': i + 1, 'at': j,
                                     'a': pa[i][max(0, j-40):j+80], 'b': pb[i][max(0, j-40):j+80]}
                break
        if res['first_diff'] is None and len(pa) != len(pb):
            res['first_diff'] = {'page': n + 1, 'note': 'page count differs'}
    print(json.dumps(res, ensure_ascii=False, indent=2))
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as f:
            json.dump(res, f, ensure_ascii=False, indent=2)

if __name__ == '__main__':
    main()
