#!/usr/bin/env python3
"""
fetch_ingu.py - 행정안전부 주민등록 인구 오픈API 수집.

  AGE  admmSexdAgePpltn/selectAdmmSexdAgePpltn  행정동별 성/연령별 주민등록 인구수 (lv=3: 시군구 코드 아래 행정동)
  HH   stdgPpltnHhStus/selectStdgPpltnHhStus    법정동별 주민등록 인구 및 세대현황 (lv=3: 시군구 코드 아래 법정동, 군 지역은 리까지)

  - 한 번 호출에 기간은 최대 3개월(4개월 이상은 QUERY_PERIOD_LIMIT_EXCEEDED_ERROR).
  - regSeCd=1 은 전체(거주자+거주불명자+재외국민).
  - 호출 결과는 _rawdata/cache/ 에 조각별로 저장되고 재실행하면 이어서 한다(일일 호출 한도 약 1만 회).
  - 마지막에 월별 압축 파일 _rawdata/age/{YYYYMM}.json.gz, _rawdata/hh/{YYYYMM}.json.gz 를 만든다.

사용: python scripts/fetch_ingu.py [--months 24] [--end 202609] [--workers 4]
키: 환경변수 DATA_GO_KR_API_KEY (없으면 ../hosppass/.env 의 API_KEY — 로컬 전용)
종료 코드: 0 정상, 2 호출 한도·연속 오류로 중단(캐시는 보존)
"""
import argparse, gzip, json, os, sys, threading, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).parent.parent
RAW = ROOT / "_rawdata"
CACHE = RAW / "cache"
BASE = "https://apis.data.go.kr/1741000"
AGE = BASE + "/admmSexdAgePpltn/selectAdmmSexdAgePpltn"
HH = BASE + "/stdgPpltnHhStus/selectStdgPpltnHhStus"
ROOT_CODE = "1100000000"      # lv=1 은 코드와 상관없이 전체 시도를 돌려준다


def get_key():
    k = os.environ.get("DATA_GO_KR_API_KEY")
    if k:
        return k
    p = ROOT.parent / "hosppass" / ".env"
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            if line.startswith("API_KEY="):
                return line.split("=", 1)[1].strip()
    raise SystemExit("DATA_GO_KR_API_KEY 가 없습니다.")


KEY = get_key()
STOP = threading.Event()
CALLS = {"n": 0}
LOCK = threading.Lock()


class QuotaError(Exception):
    pass


def call(url, **p):
    """한 번 호출(재시도 포함). 반환: (head, items). 한도 초과면 QuotaError."""
    params = dict(p, serviceKey=KEY, type="JSON")
    last = None
    for attempt in range(6):
        if STOP.is_set():
            raise QuotaError("중단")
        try:
            with LOCK:
                CALLS["n"] += 1
            r = requests.get(url, params=params, timeout=90)
            txt = r.text
            if "LIMITED_NUMBER_OF_SERVICE_REQUESTS" in txt or "SERVICE_KEY_IS_NOT_REGISTERED" in txt:
                raise QuotaError(txt[:200].replace(KEY, "***"))
            raw = r.json()
            if "Response" not in raw:           # 게이트웨이 오류(SERVICETIMEOUT_ERROR 등)
                raise RuntimeError("gateway: " + json.dumps(raw, ensure_ascii=False)[:120])
            j = raw["Response"]
            head = j.get("head", {})
            msg = head.get("resultMsg", "")
            if msg == "NODATA_ERROR":
                return head, []
            if msg != "NORMAL_SERVICE":
                if "PER_SECOND" in msg or "TRAFFIC" in msg.upper():
                    time.sleep(10 * (attempt + 1))
                    continue
                raise RuntimeError(f"{msg} {p}")
            items = (j.get("items") or {}).get("item") or []
            if isinstance(items, dict):
                items = [items]
            return head, items
        except QuotaError:
            raise
        except Exception as e:           # 타임아웃·연결 끊김·일시 오류는 재시도
            last = e
            time.sleep(4 * (attempt + 1))
    raise RuntimeError(f"호출 실패: {type(last).__name__} {str(last)[:120].replace(KEY, '***')}")


def call_all(url, **p):
    items, page = [], 1
    while True:
        head, got = call(url, numOfRows="1000", pageNo=str(page), **p)
        items += got
        total = int(head.get("totalCount") or 0)
        if len(items) >= total or not got:
            return items
        page += 1


def month_add(ym, n):
    y, m = divmod(int(ym[:4]) * 12 + int(ym[4:]) - 1 + n, 12)
    return f"{y:04d}{m + 1:02d}"


def windows(end, months):
    """end 월부터 거꾸로 3개월씩 묶은 (from, to) 목록."""
    out, cur = [], end
    start = month_add(end, -(months - 1))
    while cur >= start:
        fr = max(month_add(cur, -2), start)
        out.append((fr, cur))
        cur = month_add(fr, -1)
    return out[::-1]


def sigungu_codes():
    p = CACHE / "sigungu.json"
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    head, provs = call(AGE, admmCd=ROOT_CODE, srchFrYm=END, srchToYm=END, lv="1", regSeCd="1", numOfRows="100", pageNo="1")
    out = {}
    for pv in provs:
        _, rows = call(AGE, admmCd=pv["admmCd"], srchFrYm=END, srchToYm=END, lv="2", regSeCd="1", numOfRows="1000", pageNo="1")
        for r in rows:
            out[r["admmCd"]] = [r.get("ctpvNm"), r.get("sggNm")]
    CACHE.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    return out


def top_level_codes(out):
    """시(구가 있는 시)를 조회하면 아래 모든 구의 행이 함께 오므로 구 코드는 따로 조회하지 않는다."""
    return {k: v for k, v in out.items() if not (k[:4] + "000000" in out and k != k[:4] + "000000")}


def _fetch(api, code, fr, to):
    if api == "age":
        return call_all(AGE, admmCd=code, srchFrYm=fr, srchToYm=to, lv="3", regSeCd="1")
    return call_all(HH, stdgCd=code, srchFrYm=fr, srchToYm=to, lv="3", regSeCd="1")


def task(api, code, fr, to):
    f = CACHE / f"{api}_{code}_{fr}_{to}.json"
    if f.exists():
        return 0
    try:
        items = _fetch(api, code, fr, to)
    except RuntimeError:
        # 행이 아주 많은 지역(군 지역의 리 단위 등)은 3개월 조회가 게이트웨이 시간 초과가 날 수 있어 월별로 나눠 다시 받는다
        items, m = [], fr
        while m <= to:
            items += _fetch(api, code, m, m)
            m = month_add(m, 1)
    f.write_text(json.dumps(items, ensure_ascii=False), encoding="utf-8")
    return len(items)


def age_row(it):
    g = lambda k: int(it.get(k) or 0)
    ages = [g(f"male{a}AgeNmprCnt") for a in range(0, 101, 10)] + [g(f"feml{a}AgeNmprCnt") for a in range(0, 101, 10)]
    return [it["admmCd"], it.get("ctpvNm"), it.get("sggNm"), it.get("dongNm"), g("totNmprCnt"), g("maleNmprCnt"), g("femlNmprCnt"), ages]


def hh_row(it):
    g = lambda k: int(it.get(k) or 0)
    return [it["stdgCd"], it.get("ctpvNm"), it.get("sggNm"), it.get("stdgNm") or "", it.get("liNm") or "", g("totNmprCnt"), g("maleNmprCnt"), g("femlNmprCnt"), g("hhCnt")]


def pack(months_list, apis=("age", "hh")):
    for kind, conv in (("age", age_row), ("hh", hh_row)):
        if kind not in apis:
            continue
        by = {m: {} for m in months_list}
        for f in CACHE.glob(f"{kind}_*.json"):
            for it in json.loads(f.read_text(encoding="utf-8")):
                ym = it.get("statsYm")
                if ym in by:
                    row = conv(it)
                    by[ym][row[0] + "|" + (row[4] if kind == "hh" else "")] = row   # 같은 코드 중복(시 아래 구 중복 조회) 제거
        d = RAW / kind
        d.mkdir(parents=True, exist_ok=True)
        for ym, rows in by.items():
            if rows:
                with gzip.open(d / f"{ym}.json.gz", "wt", encoding="utf-8") as fh:
                    json.dump(list(rows.values()), fh, ensure_ascii=False, separators=(",", ":"))
        print(kind, {ym: len(r) for ym, r in by.items() if r})


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--months", type=int, default=24)
    ap.add_argument("--end", default="")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--apis", default="age,hh", help="수집할 API: age(행정동 성/연령별), hh(법정동 인구·세대). 행정동 자료는 fetch_files.py 로 받는 편이 훨씬 빠르다")
    a = ap.parse_args()
    APIS = tuple(a.apis.split(","))
    CACHE.mkdir(parents=True, exist_ok=True)
    # 최신 월 판별: 요청한 end 에서 시작해 NODATA 이면 한 달씩 뒤로
    END = a.end or time.strftime("%Y%m", time.localtime(time.time() - 86400 * 20))
    for _ in range(4):
        h, rows = call(AGE, admmCd="1168000000", srchFrYm=END, srchToYm=END, lv="3", regSeCd="1", numOfRows="5", pageNo="1")
        if rows:
            break
        END = month_add(END, -1)
    print("최신 월:", END)
    sgg = top_level_codes(sigungu_codes())
    print("조회할 시군구 코드:", len(sgg), flush=True)
    wins = windows(END, a.months)
    # 최신 창부터 받는다(앞부분만 끝나도 페이지 개발·최근 추이 검증을 시작할 수 있게)
    jobs = [(api, code, fr, to) for (fr, to) in wins[::-1] for code in sgg for api in APIS]
    todo = [j for j in jobs if not (CACHE / f"{j[0]}_{j[1]}_{j[2]}_{j[3]}.json").exists()]
    print(f"작업 {len(jobs)}건 중 남은 것 {len(todo)}건, 창 {len(wins)}개")
    done, fail = 0, 0
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        futs = {ex.submit(task, *j): j for j in todo}
        for fu in as_completed(futs):
            try:
                fu.result()
                done += 1
            except QuotaError as e:
                print("한도/중단:", e)
                STOP.set()
                fail += 1
            except Exception as e:
                print("실패:", futs[fu], e)
                fail += 1
            if (done + fail) % 100 == 0:
                print(f"진행 {done + fail}/{len(todo)} 실패 {fail} 호출 {CALLS['n']} 경과 {time.time() - t0:.0f}s", flush=True)
    print(f"완료 {done}, 실패 {fail}, 호출 {CALLS['n']}")
    months_list = []
    cur = END
    for _ in range(a.months):
        months_list.append(cur)
        cur = month_add(cur, -1)
    pack(months_list, APIS)
    sys.exit(2 if fail else 0)
