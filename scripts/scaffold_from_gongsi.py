#!/usr/bin/env python3
"""scaffold_from_gongsi.py - 우아공시가의 공용 뼈대(CSS·JS·include·개인정보·robots·deploy·기본 레이아웃)를 복사해 우아인구용으로 치환한다(1회성)."""
import re, shutil, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
SRC = Path(r"C:\개인\wooahouse\wooagongsi")
DST = Path(r"C:\개인\wooahouse\wooaingu")

COLORS = {            # 스카이블루 → 바이올렛
    "#0369A1": "#6D28D9", "#0369a1": "#6D28D9",
    "#0EA5E9": "#8B5CF6", "#0ea5e9": "#8B5CF6",
    "#075985": "#5B21B6", "#0c4a6e": "#4C1D95",
    "#0C4A6E": "#4C1D95",
    "#F0F9FF": "#F5F3FF", "#f0f9ff": "#F5F3FF",
    "#E0F2FE": "#EDE9FE", "#e0f2fe": "#EDE9FE",
    "#BAE6FD": "#DDD6FE", "#bae6fd": "#DDD6FE",
    "#7DD3FC": "#C4B5FD", "#7dd3fc": "#C4B5FD",
}
TEXT = [("wooagongsi", "wooaingu"), ("우아공시가", "우아인구")]


def conv(text):
    for a, b in COLORS.items():
        text = text.replace(a, b)
    for a, b in TEXT:
        text = text.replace(a, b)
    return text


def copy(rel, convert=True):
    s, d = SRC / rel, DST / rel
    d.parent.mkdir(parents=True, exist_ok=True)
    if convert:
        d.write_text(conv(s.read_text(encoding="utf-8")), encoding="utf-8")
    else:
        shutil.copyfile(s, d)
    print("복사:", rel)


for rel in ["assets/css/main.css", "assets/js/ad-dev-placeholder.js", "assets/js/wooa-sidebar.js", "assets/js/wooa-sites-bar.js",
            "_includes/ad.html", "_includes/faq.html", "privacy/index.html", "robots.txt", "CNAME", "Gemfile", "Gemfile.lock",
            ".github/workflows/deploy.yml", "assets/og-image.png"]:
    copy(rel, convert=not (rel.startswith("assets/js") or rel.endswith(".png") or rel == "Gemfile.lock"))

# 기본 레이아웃: 네이버 메타(공시가 값) 제거(사용자가 새 값을 줄 때까지), 내비·푸터 문구 교체
p = DST / "_layouts" / "default.html"
p.parent.mkdir(parents=True, exist_ok=True)
s = (SRC / "_layouts" / "default.html").read_text(encoding="utf-8")
s = conv(s)
s = re.sub(r'\s*<meta name="naver-site-verification"[^>]*/>\n', "\n", s)
s = s.replace("우아인구 - 아파트·빌라 공시가격 조회와 추이", "우아인구 - 우리 동네 인구·세대수·연령별 구성")
s = s.replace("🏷️", "👥")
s = s.replace("page.layout == 'complex'", "page.layout == 'beop'")
s = s.replace("page.layout == 'rank' or", "page.layout == 'rank' or page.layout == 'rankindex' or")
s = s.replace('<a href="{{ \'/region/\' | relative_url }}">지역별</a>', '<a href="{{ \'/region/\' | relative_url }}">지역별</a>')
i = s.find('<p class="footer-disclaimer">')
j = s.find("</p>", i) + 4
disc = '''<p class="footer-disclaimer">
      인구·세대 통계는 행정안전부 주민등록 인구통계(공공데이터포털, 매월 말일 기준 주민등록 거주자·거주불명자·재외국민 포함)를 읍면동 단위로 정리한 것입니다. 통계청 인구총조사(실제 거주 기준)와 수치가 다를 수 있습니다.<br>
      주민등록 인구는 주민등록상 주소지 기준이라 실제 거주 인구와 차이가 있을 수 있으며, 연령대는 만 나이 10세 단위(0~9세, 10~19세 …) 구간입니다.
    </p>'''
s = s[:i] + disc + s[j:]
fl = s.find('<p class="footer-links">')
fe = s.find("</p>", fl) + 4
links = '''<p class="footer-links">
      <a href="https://wooahouse.com">WooaHouse</a> ·
      <a href="https://wooatown.wooahouse.com">우아동네</a> ·
      <a href="https://wooasanggwon.wooahouse.com">우아상권</a> ·
      <a href="https://wooahakgun.wooahouse.com">우아학군</a> ·
      <a href="https://wooaapt.wooahouse.com">우아아파트</a> ·
      <a href="{{ '/privacy/' | relative_url }}">개인정보처리방침</a>
    </p>'''
s = s[:fl] + links + s[fe:]
p.write_text(s, encoding="utf-8")
print("기본 레이아웃 정리 완료")

# 정적 페이지: 지역별(region) 인덱스는 템플릿 파일로 직접 작성하므로 여기서는 복사하지 않는다.
