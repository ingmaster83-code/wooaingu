#!/bin/bash
# 월간 갱신: ① 행정동 월별 파일(성·연령별/1인세대/세대원수) 최근 3개월 → ② 법정동 오픈API 최근 3개월 → ③ JSON 집계(build_data).
# 월별 요약 이력(_rawdata/ingu_hist.json.gz)은 저장소에 커밋돼 있어 이전 달 원본 CSV 없이도 이어서 쌓인다.
# 하나라도 실패하면 비정상 종료해 빌드·배포를 막는다(기존 배포 유지).
set -e
cd "$(dirname "$0")/.."
mkdir -p data/raw
python scripts/fetch_files.py --latest
python scripts/fetch_ingu.py --months 3 --workers 8 --apis hh
python scripts/build_data.py
