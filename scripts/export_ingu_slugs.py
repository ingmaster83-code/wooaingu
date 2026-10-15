#!/usr/bin/env python3
"""
export_ingu_slugs.py - 다른 사이트가 우아인구로 링크를 걸 때 쓰는 "어떤 동네 페이지가 있는지" 목록을 내보낸다.

출력(JSON): {"dong": {"시도|시군구|동이름": "dong/시도/시군구/동이름" 또는 "beop/..."}, "sg": {"시도|시군구": "region/시도/시군구"}}
  - 다른 사이트의 지역 표기와 맞추기 위해 별칭 키도 함께 넣는다: 전남광주 통합(2026) 이전 표기('광주'·'전남'), 구가 있는 시의 띄어쓰기 없는 표기('천안시동남구').
  - 값은 우아인구 안의 실제 경로(통합 후 표기)라서 링크는 별칭으로 찾아도 올바른 페이지로 간다.
대상: 우아상권·우아학군의 _data/ingu_slugs.json, 우아동네의 scripts/ingu_slugs.json
우아인구 데이터(_rawdata/ingu_dong.json, ingu_beop.json)를 갱신해 다시 만들면 이 스크립트도 다시 실행해 각 사이트에 반영한다.
"""
import json, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).parent.parent
BASE = ROOT.parent
TARGETS = [BASE / "wooasanggwon" / "_data" / "ingu_slugs.json", BASE / "wooahakgun" / "_data" / "ingu_slugs.json", BASE / "wooatown" / "scripts" / "ingu_slugs.json"]
GWANGJU = {"동구", "서구", "남구", "북구", "광산구"}          # 통합 전 광주광역시 자치구(나머지는 전남)


def variants(do, sg):
    dos = [do]
    if do == "전남광주":
        dos.append("광주" if sg in GWANGJU else "전남")
    sgs = [sg]
    if " " in sg:
        sgs.append(sg.replace(" ", ""))
    return [(d, s) for d in dos for s in sgs]


def main():
    dongs = json.loads((ROOT / "_rawdata" / "ingu_dong.json").read_text(encoding="utf-8"))
    beops = json.loads((ROOT / "_rawdata" / "ingu_beop.json").read_text(encoding="utf-8"))
    out = {"dong": {}, "sg": {}}
    for b in beops:
        if not b.get("sg"):
            continue
        for d, s in variants(b["do"], b["sg"]):
            out["dong"][f"{d}|{s}|{b['name']}"] = f"beop/{b['do']}/{b['sg']}/{b['name']}"
    for r in dongs:
        for d, s in variants(r["do"], r["sg"]):
            out["dong"][f"{d}|{s}|{r['dong']}"] = f"dong/{r['do']}/{r['sg']}/{r['dong']}"      # 같은 이름이면 행정동 페이지를 우선
            out["sg"][f"{d}|{s}"] = f"region/{r['do']}/{r['sg']}"
        if " " in r["sg"]:
            city = r["sg"].split(" ")[0]
            for d, _ in variants(r["do"], r["sg"]):
                out["sg"][f"{d}|{city}"] = f"region/{r['do']}/{city}"
    text = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    for t in TARGETS:
        t.parent.mkdir(parents=True, exist_ok=True)
        t.write_text(text, encoding="utf-8")
        print("쓰기:", t, len(text) // 1000, "KB")
    print("동네 키", len(out["dong"]), "시군구·시 키", len(out["sg"]))


if __name__ == "__main__":
    main()
