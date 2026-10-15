#!/usr/bin/env python3
"""
fetch_files.py - 공공데이터포털 행안부 '지역별(행정동)' 주민등록 파일 3종의 월별 버전을 내려받는다.

  15097972  지역별(행정동) 성별 연령별 주민등록 인구수       → data/raw/age/{YYYYMM}.csv
  15097973  지역별(행정동) 성별 연령별 주민등록 1인세대수     → data/raw/one/{YYYYMM}.csv
  15097974  지역별(행정동) 세대원수별 주민등록 세대수         → data/raw/size/{YYYYMM}.csv

각 데이터셋은 현재 버전 + 과거 데이터 목록(selectHistAndCsvData.do)에 월별 전국 CSV가 쌓여 있다(2022년부터 약 55개월).
오픈API(호출 한도·느림)와 달리 월 1회 다운로드로 전국 행정동을 받는다. 이미 받은 월은 건너뛴다.
사용: python scripts/fetch_files.py [--from 202201] [--only age,one,size] [--latest]
"""
import argparse, re, sys, time
from pathlib import Path

import requests

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).parent.parent
RAW = ROOT / "data" / "raw"
DATASETS = {"age": "15097972", "one": "15097973", "size": "15097974"}
S = requests.Session()
UA = {"User-Agent": "Mozilla/5.0"}


def hdr(pk):
    return {"X-Requested-With": "XMLHttpRequest", "Referer": f"https://www.data.go.kr/data/{pk}/fileData.do", "User-Agent": "Mozilla/5.0"}


def versions(pk):
    """(ym, uddi, name) 목록 — 현재 버전 포함, 월 중복은 첫 항목(최신 등록)만."""
    page = S.get(f"https://www.data.go.kr/data/{pk}/fileData.do", headers=UA, timeout=60).text
    cur = re.search(r"uddi:[0-9a-f-]+", page).group(0)
    r = S.post("https://www.data.go.kr/tcs/dss/selectHistAndCsvData.do", data={"publicDataPk": pk, "publicDataDetailPk": cur}, headers=hdr(pk), timeout=60)
    rows = re.findall(r'data-public-pk="(uddi:[^"]+)"\s+data-public-detail-sn="(\d+)"\s*>\s*([^<]+?)\s*</a>\s*</td>\s*<td>(\d{4}-\d{2}-\d{2})</td>', r.text)
    out, seen = [], set()
    # 현재 버전(이름은 상세페이지 제목에서)은 history 의 첫 줄과 같은 월일 수 있다
    for uddi, sn, name, reg in rows:
        m = re.search(r"_(\d{6})\d{2}$", name.strip())
        if not m or m.group(1) in seen:
            continue
        seen.add(m.group(1))
        out.append((m.group(1), uddi, name.strip()))
    return cur, out


def download(pk, uddi, out):
    for sn in ("1", "2", "3"):
        r = S.post("https://www.data.go.kr/tcs/dss/selectFileDataDownload.do",
                   data={"publicDataDetailPk": uddi, "publicDataPk": pk, "atchFileId": "", "fileDetailSn": sn, "publicDataTyCode": "PR0051"}, headers=hdr(pk), timeout=60)
        try:
            j = r.json()
        except Exception:
            continue
        if j.get("status") and j.get("atchFileId"):
            break
    else:
        raise RuntimeError("다운로드 정보를 얻지 못함")
    resp = S.get("https://www.data.go.kr/cmm/cmm/fileDownload.do", params={"atchFileId": j["atchFileId"], "fileDetailSn": j["fileDetailSn"]}, headers=UA, timeout=(30, 300))
    resp.raise_for_status()
    cd = resp.headers.get("Content-Disposition", "")
    try:
        fname = cd.encode("latin-1").decode("utf-8")
    except Exception:
        fname = cd
    return resp.content, fname


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="start", default="202201")
    ap.add_argument("--only", default="age,one,size")
    ap.add_argument("--latest", action="store_true", help="가장 최근 3개월만(월간 갱신용)")
    a = ap.parse_args()
    for kind in a.only.split(","):
        pk = DATASETS[kind]
        cur, vs = versions(pk)
        vs = [v for v in vs if v[0] >= a.start]
        if a.latest:
            vs = vs[:3]
        print(kind, pk, "버전", len(vs), vs[0][0] if vs else None, "~", vs[-1][0] if vs else None, flush=True)
        # 현재 버전(history 목록에는 없고 상세페이지의 최신 파일)은 파일명에서 월을 읽는다
        todo = [(None, cur, "현재")] + vs
        for ym, uddi, name in todo:
            out = RAW / kind / f"{ym}.csv" if ym else None
            if out is not None and out.exists() and out.stat().st_size > 1000 and not a.latest:
                continue
            for attempt in range(4):
                try:
                    body, fname = download(pk, uddi, out)
                    if ym is None:
                        m = re.search(r"_(\d{6})\d{2}", fname)
                        if not m:
                            raise RuntimeError("현재 버전 파일명에서 월을 못 찾음: " + fname[:80])
                        ym = m.group(1)
                        out = RAW / kind / f"{ym}.csv"
                    out.parent.mkdir(parents=True, exist_ok=True)
                    out.write_bytes(body)
                    print("  ", ym, len(body) // 1000, "KB", flush=True)
                    break
                except Exception as e:
                    print("  ", ym, "재시도", attempt + 1, str(e)[:80], flush=True)
                    time.sleep(3 * (attempt + 1))
            else:
                print("  ", ym, "실패", flush=True)
                sys.exit(2)
            time.sleep(0.5)


if __name__ == "__main__":
    main()
