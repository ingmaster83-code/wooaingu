#!/usr/bin/env python3
"""
add_backlinks.py - 우아상권·우아학군 레이아웃에 우아인구 링크(동 페이지 또는 시군구 페이지)를 넣는다(1회성, 재실행해도 중복 삽입 안 함).
링크 경로는 _data/ingu_slugs.json(export_ingu_slugs.py)에서 찾는다: 동 페이지가 있으면 동 링크, 없으면 시군구 링크, 둘 다 없으면 링크를 만들지 않는다.
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
BASE = Path(__file__).parent.parent.parent
MARK = "wooaingu.wooahouse.com"

DONG_SNIPPET = """{% assign ikey = page.doShort | append: "|" | append: page.sigungu | append: "|" | append: page.dong %}{% assign ipath = site.data.ingu_slugs.dong[ikey] %}{% assign iskey = page.doShort | append: "|" | append: page.sigungu %}{% assign isg = site.data.ingu_slugs.sg[iskey] %}{% if ipath %}<a href="https://wooaingu.wooahouse.com/{{ ipath }}/">{{ page.dong }} 인구·세대수 →</a> {% elsif isg %}<a href="https://wooaingu.wooahouse.com/{{ isg }}/">{{ page.sigungu }} 인구·세대수 →</a> {% endif %}"""
SG_SNIPPET = """{% assign iskey = page.doShort | append: "|" | append: page.sigungu %}{% assign isg = site.data.ingu_slugs.sg[iskey] %}{% if isg %}<a href="https://wooaingu.wooahouse.com/{{ isg }}/">{{ page.sigungu }} 인구·세대수 →</a> {% endif %}"""

# (파일, 삽입 기준 문자열, 스니펫) — 기준 문자열 바로 앞에 스니펫을 넣는다
EDITS = [
    ("wooasanggwon/_layouts/dong.html", '<a href="/rank/">상권 랭킹 →</a>', DONG_SNIPPET),
    ("wooasanggwon/_layouts/sg.html", '<a href="/biz/">업종별 보기 →</a>', SG_SNIPPET),
    ("wooahakgun/_layouts/dong.html", '<a href="https://wooaapt.wooahouse.com/region/', DONG_SNIPPET),
    ("wooahakgun/_layouts/sigungu.html", '<a href="/guide/">학군 고르는 방법 →</a></p>', SG_SNIPPET),
    ("wooahakgun/_layouts/apt.html", '<a href="/chopuma/{{ page.doShort | uri_escape }}/">', DONG_SNIPPET),
]


def main():
    for rel, anchor, snippet in EDITS:
        p = BASE / rel
        s = p.read_text(encoding="utf-8")
        if MARK in s:
            print("이미 있음:", rel)
            continue
        i = s.find(anchor)
        if i < 0:
            print("기준 문자열 없음:", rel, anchor[:40])
            continue
        s = s[:i] + snippet + s[i:]
        p.write_text(s, encoding="utf-8")
        print("추가:", rel)


if __name__ == "__main__":
    main()
