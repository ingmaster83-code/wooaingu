#!/usr/bin/env python3
"""
build_data.py - 행안부 월별 주민등록 파일(행정동 단위)과 법정동 API 수집분을 Jekyll 생성기용 JSON 으로 만든다.

입력
  data/raw/age/{YYYYMM}.csv    행정동 성별·연령별(0~110세 이상) 인구  (fetch_files.py)
  data/raw/one/{YYYYMM}.csv    행정동 성별·연령별 1인세대수           (fetch_files.py)
  data/raw/size/{YYYYMM}.csv   행정동 세대원수별 세대수              (fetch_files.py)
  _rawdata/hh/{YYYYMM}.json.gz 법정동 인구·세대(리 포함, 최근 3개월)    (fetch_ingu.py --apis hh)
  _rawdata/ingu_hist.json.gz   월별 행정동 요약 이력(이 스크립트가 갱신·커밋; 원본 CSV 없이도 이력 유지)
출력
  _rawdata/ingu_dong.json   행정동 레코드(페이지·랭킹용)
  _rawdata/ingu_beop.json   행정동과 이름이 다른 법정동 레코드(법정동 페이지용)
  _rawdata/ingu_meta.json   기준월·전국 합계 등
  _rawdata/ingu_hist.json.gz
"""
import csv, gzip, json, re, sys
from collections import defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).parent.parent
RAW = ROOT / "_rawdata"
FILES = ROOT / "data" / "raw"

DO = {"서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천", "광주광역시": "광주", "대전광역시": "대전",
      "울산광역시": "울산", "세종특별자치시": "세종", "경기도": "경기", "강원특별자치도": "강원", "강원도": "강원", "충청북도": "충북", "충청남도": "충남",
      "전북특별자치도": "전북", "전라북도": "전북", "전라남도": "전남", "경상북도": "경북", "경상남도": "경남", "제주특별자치도": "제주",
      "전남광주통합특별시": "전남광주"}
AGE_RE = re.compile(r"^(\d+)세(이상)?\s*(남자|여자)$")
KEEP_MONTHS = 24          # 월별 표로 보여줄 개월 수


def read_csv(path):
    last = None
    for enc in ("utf-8-sig", "cp949"):
        try:
            with open(path, encoding=enc, newline="") as fh:
                return list(csv.reader(fh))
        except UnicodeDecodeError as e:
            last = e
    raise last


def parse_age_file(path):
    """행정기관코드 → {do, sg, dong, tot, m[111], f[111]}"""
    rows = read_csv(path)
    head = rows[0]
    cols = []
    for i, h in enumerate(head):
        m = AGE_RE.match(h.strip())
        if m:
            cols.append((i, int(m.group(1)), 0 if m.group(3) == "남자" else 1))
    out = {}
    for r in rows[1:]:
        if len(r) < 8 or not r[0].strip():
            continue
        m, f = [0] * 111, [0] * 111
        for i, age, sx in cols:
            try:
                v = int(r[i] or 0)
            except (ValueError, IndexError):
                v = 0
            (m if sx == 0 else f)[min(age, 110)] += v
        tot = sum(m) + sum(f)
        out[r[0].strip()] = {"ctpv": r[2], "sg": r[3], "dong": r[4], "tot": tot, "m": m, "f": f}
    return out


def parse_size_file(path):
    rows = read_csv(path)
    out = {}
    for r in rows[1:]:
        if len(r) < 16 or not r[0].strip():
            continue
        try:
            v = [int(x or 0) for x in r[5:16]]          # 전체, 1인 … 9인, 10인이상
        except ValueError:
            continue
        out[r[0].strip()] = v
    return out


def main():
    # ── 월별 이력 갱신 ─────────────────────────────────────
    hist_path = RAW / "ingu_hist.json.gz"
    hist = {}
    if hist_path.exists():
        with gzip.open(hist_path, "rt", encoding="utf-8") as fh:
            hist = json.load(fh)
    age_months = sorted(p.stem for p in (FILES / "age").glob("*.csv"))
    if not age_months:
        raise SystemExit("data/raw/age 에 파일이 없습니다. 먼저 scripts/fetch_files.py 를 실행하세요.")
    cache = {}
    for ym in age_months:
        ap = FILES / "age" / f"{ym}.csv"
        sp = FILES / "size" / f"{ym}.csv"
        a = parse_age_file(ap)
        s = parse_size_file(sp) if sp.exists() else {}
        h = {}
        for code, d in a.items():
            if d["tot"] <= 0:
                continue
            old = sum(d["m"][65:]) + sum(d["f"][65:])
            kid = sum(d["m"][:15]) + sum(d["f"][:15])
            sz = s.get(code)
            h[code] = [d["tot"], sz[0] if sz else 0, sz[1] if sz else 0, old, kid]
        hist[ym] = h
        cache[ym] = (a, s)
    months = sorted(hist)
    latest = months[-1]
    print("월:", months[0], "~", latest, f"({len(months)}개월)")
    if len(months) >= 2 and len(hist[latest]) < 0.9 * len(hist[months[-2]]):
        raise SystemExit(f"최신 월({latest}) 행정동 {len(hist[latest])}개가 직전 월 {len(hist[months[-2]])}개의 90% 미만입니다. 수집이 덜 끝난 것 같아 중단합니다.")
    with gzip.open(hist_path, "wt", encoding="utf-8") as fh:
        json.dump(hist, fh, ensure_ascii=False, separators=(",", ":"))

    # ── 최신 월 상세 + 1인세대 연령 ────────────────────────
    a_lat, s_lat = cache[latest] if latest in cache else (parse_age_file(FILES / "age" / f"{latest}.csv"), parse_size_file(FILES / "size" / f"{latest}.csv"))
    one_path = FILES / "one" / f"{latest}.csv"
    one = parse_age_file(one_path) if one_path.exists() else {}

    def month_back(ym, n):
        t = int(ym[:4]) * 12 + int(ym[4:]) - 1 - n
        return f"{t // 12:04d}{t % 12 + 1:02d}"

    keep = [month_back(latest, i) for i in range(KEEP_MONTHS - 1, -1, -1)]
    yrs = [month_back(latest, 12 * i) for i in range(5, -1, -1)]          # 같은 달 기준 연도별
    dongs = []
    for code, d in a_lat.items():
        if d["tot"] <= 0 or not d["dong"]:
            continue
        m, f = d["m"], d["f"]
        tot = d["tot"]
        male, fem = sum(m), sum(f)
        a5m = [sum(m[i * 5:(i + 1) * 5]) for i in range(20)] + [sum(m[100:])]
        a5f = [sum(f[i * 5:(i + 1) * 5]) for i in range(20)] + [sum(f[100:])]
        agm = [sum(m[i * 10:(i + 1) * 10]) for i in range(8)] + [sum(m[80:])]
        agf = [sum(f[i * 10:(i + 1) * 10]) for i in range(8)] + [sum(f[80:])]
        ages = [m[i] + f[i] for i in range(111)]
        avg = sum((i + 0.5) * n for i, n in enumerate(ages)) / tot
        acc, med = 0, 0
        for i, n in enumerate(ages):
            acc += n
            if acc >= tot / 2:
                med = i
                break
        sg = d["sg"].strip() or ("세종시" if d["ctpv"].startswith("세종") else d["ctpv"])        # 세종은 시군구명이 비어 있다
        rec = {"id": code, "do": DO.get(d["ctpv"], d["ctpv"]), "sg": sg, "dong": d["dong"], "tot": tot, "male": male, "fem": fem,
               "a5m": a5m, "a5f": a5f, "ag": [x + y for x, y in zip(agm, agf)], "agm": agm, "agf": agf,
               "old65": sum(ages[65:]), "kid14": sum(ages[:15]), "avg": round(avg, 1), "med": med}
        sz = s_lat.get(code)
        if sz and sz[0] > 0:
            rec["hh"] = sz[0]
            rec["hs"] = [sz[1], sz[2], sz[3], sz[4], sum(sz[5:])]               # 1·2·3·4·5인 이상
        o = one.get(code)
        if o and rec.get("hh"):
            om, of = o["m"], o["f"]
            def grp(arr):
                g = [sum(arr[:20])] + [sum(arr[i * 10:(i + 1) * 10]) for i in range(2, 8)] + [sum(arr[80:])]
                return g
            rec["o8"] = [x + y for x, y in zip(grp(om), grp(of))]               # 19세 이하, 20대 … 70대, 80세 이상
            rec["o8f"] = grp(of)
        rec["tr"] = [[ym] + hist[ym][code] for ym in keep if ym in hist and code in hist[ym]]
        rec["yr"] = [[ym] + hist[ym][code] for ym in yrs if ym in hist and code in hist[ym]]
        dongs.append(rec)
    print("행정동:", len(dongs), "/ 세대 연결:", sum(1 for d in dongs if "hh" in d), "/ 1인세대 연령:", sum(1 for d in dongs if "o8" in d))

    # ── 법정동(리 포함) — 오픈API 수집분 ───────────────────
    hh = {}
    for f in sorted((RAW / "hh").glob("*.json.gz")) if (RAW / "hh").exists() else []:
        with gzip.open(f, "rt", encoding="utf-8") as fh:
            hh[f.name.split(".")[0]] = json.load(fh)
    beop_pages, ri_by7 = [], defaultdict(list)
    if hh:
        hser = defaultdict(dict)
        for ym, rows in hh.items():
            for r in rows:
                hser[r[0]][ym] = [r[5], r[8]]
        hlatest = hh[max(hh)]
        beops = []
        li_groups = {}                       # 군 지역: 읍·면(법정동) 아래 리 행들을 합산해 읍·면 레코드로 만든다
        for r in hlatest:
            code, ctpv, sg, nm, ri, tot, male, fem, hhc = r
            sg = sg or ("세종시" if (ctpv or "").startswith("세종") else ctpv)        # 세종은 시군구명이 비어 있다
            if ri:
                ri_by7[code[:7]].append([ri, tot, hhc])
                g = li_groups.setdefault((ctpv, sg, nm, code[:7]), {"codes": [], "tot": 0, "male": 0, "fem": 0, "hh": 0})
                g["codes"].append(code)
                g["tot"] += tot
                g["male"] += male
                g["fem"] += fem
                g["hh"] += hhc
                continue
            if not nm or tot <= 0:
                continue
            beops.append({"id": code, "do": DO.get(ctpv, ctpv), "sg": sg, "name": nm, "tot": tot, "male": male, "fem": fem, "hh": hhc,
                          "ym": max(hh), "tr": [[ym, hser[code][ym][0], hser[code][ym][1]] for ym in sorted(hser[code])]})
        for (ctpv, sg, nm, c7), g in li_groups.items():
            if not nm or g["tot"] <= 0:
                continue
            months_here = sorted({ym for c in g["codes"] for ym in hser[c]})
            tr = []
            for ym in months_here:
                vals = [hser[c][ym] for c in g["codes"] if ym in hser[c]]
                if len(vals) == len(g["codes"]):                 # 모든 리가 있는 달만(합계 왜곡 방지)
                    tr.append([ym, sum(v[0] for v in vals), sum(v[1] for v in vals)])
            beops.append({"id": c7 + "000", "do": DO.get(ctpv, ctpv), "sg": sg, "name": nm, "tot": g["tot"], "male": g["male"], "fem": g["fem"], "hh": g["hh"],
                          "ym": max(hh), "tr": tr})
        for d in dongs:
            lst = ri_by7.get(d["id"][:7])
            if lst:
                d["ri"] = sorted(lst, key=lambda x: -x[1])
        dong_names = {(d["do"], d["sg"], d["dong"]) for d in dongs}

        def base(n):
            return re.sub(r"[0-9·.]+", "", n).replace("제", "") if re.search(r"[0-9]", n) else n
        by_sg = defaultdict(list)
        for d in dongs:
            by_sg[(d["do"], d["sg"])].append(d)
        for b in beops:
            if (b["do"], b["sg"], b["name"]) in dong_names:
                continue
            b["dongs"] = [d["dong"] for d in by_sg[(b["do"], b["sg"])] if base(d["dong"]) == b["name"] or base(d["dong"]).rstrip("동읍면가") == b["name"].rstrip("동읍면가")]
            beop_pages.append(b)
        print("법정동(리 제외):", len(beops), "/ 별도 페이지:", len(beop_pages), "/ 리 묶음:", len(ri_by7), "/ 법정동 기준월:", max(hh))

    # ── 전국 합계 ──
    tot_all = sum(d["tot"] for d in dongs)
    hh_all = sum(d.get("hh", 0) for d in dongs)
    pop_hh = sum(d["tot"] for d in dongs if "hh" in d)
    meta = {"ym": latest, "first": months[0], "months": months, "tot": tot_all, "hh": hh_all, "pop_hh": pop_hh,
            "h1": sum(d["hs"][0] for d in dongs if "hs" in d), "old65": sum(d["old65"] for d in dongs), "kid14": sum(d["kid14"] for d in dongs),
            "dongs": len(dongs), "beops": len(beop_pages), "beop_ym": max(hh) if hh else None}
    (RAW / "ingu_dong.json").write_text(json.dumps(dongs, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    (RAW / "ingu_beop.json").write_text(json.dumps(beop_pages, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    (RAW / "ingu_meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    print("저장:", {k: v for k, v in meta.items() if k != "months"})


if __name__ == "__main__":
    main()
