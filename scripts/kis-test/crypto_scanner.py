"""
업비트 KRW 마켓 코인 매수신호 스캐너 — 일봉 OHLCV + scanner.detect_signals → Supabase signals

일봉(candles/days)은 공개 API — UPBIT_ACCESS_KEY 없이 동작합니다.
키는 추후 거래·잔고 API 등 확장용(.env)으로만 읽습니다.

사용법:
  pip install -r requirements.txt
  cp .env.example .env
  python crypto_scanner.py              # 최근 5일
  python crypto_scanner.py --days 30
  python crypto_scanner.py --limit 10   # 테스트

GitHub Actions: .github/workflows/crypto-scanner-schedule.yml
"""

from __future__ import annotations

import argparse
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

import pandas as pd
import requests

from scanner import (
    SIGNAL_DEFS,
    detect_signals,
    notify_telegram_for_latest_day,
    upsert_batch,
)

UPBIT_API = "https://api.upbit.com/v1"
HTTP_HEADERS = {"User-Agent": "TeamSync-Crypto-Scanner/1.0"}
MARKET_TAG = "UPBIT"
CANDLE_COUNT = 120
DEFAULT_WORKERS = 8


def get_target_calendar_dates(days_back: int) -> set[str]:
    """코인은 24/7 — 최근 N **달력일**(오늘 포함)."""
    result: set[str] = set()
    d = datetime.today()
    for _ in range(max(1, days_back)):
        result.add(d.strftime("%Y-%m-%d"))
        d -= timedelta(days=1)
    return result


def fetch_krw_markets() -> list[dict]:
    resp = requests.get(
        f"{UPBIT_API}/market/all",
        params={"isDetails": "false"},
        headers=HTTP_HEADERS,
        timeout=30,
    )
    resp.raise_for_status()
    rows = resp.json()
    out: list[dict] = []
    for row in rows:
        market = str(row.get("market", "")).strip()
        if not market.startswith("KRW-"):
            continue
        out.append(
            {
                "market": market,
                "code": market,
                "name": str(row.get("korean_name") or row.get("english_name") or market).strip(),
            }
        )
    return out


def fetch_upbit_daily_ohlcv(market: str) -> pd.DataFrame | None:
    resp = requests.get(
        f"{UPBIT_API}/candles/days",
        params={"market": market, "count": CANDLE_COUNT},
        headers=HTTP_HEADERS,
        timeout=30,
    )
    if resp.status_code == 429:
        time.sleep(1.5)
        resp = requests.get(
            f"{UPBIT_API}/candles/days",
            params={"market": market, "count": CANDLE_COUNT},
            headers=HTTP_HEADERS,
            timeout=30,
        )
    if resp.status_code != 200:
        return None
    raw = resp.json()
    if not isinstance(raw, list) or not raw:
        return None

    rows = []
    for c in raw:
        kst = str(c.get("candle_date_time_kst", ""))[:10]
        if len(kst) < 10:
            continue
        rows.append(
            {
                "Date": kst,
                "Open": float(c["opening_price"]),
                "High": float(c["high_price"]),
                "Low": float(c["low_price"]),
                "Close": float(c["trade_price"]),
                "Volume": float(c.get("candle_acc_trade_volume") or 0),
            }
        )
    if not rows:
        return None
    df = pd.DataFrame(rows)
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").set_index("Date")
    return df


def _scan_one_market(item: dict, target_dates: set[str]) -> tuple[list[dict], bool]:
    """단일 마켓 스캔. (신호 rows, 오류 여부) 반환."""
    market = item["market"]
    name = item["name"]
    code = item["code"]
    try:
        df = fetch_upbit_daily_ohlcv(market)
        if df is None or df.empty:
            return [], False
        signals = detect_signals(df, target_dates)
        rows: list[dict] = []
        for s in signals:
            meta = SIGNAL_DEFS[s["signal_type"]]
            rows.append(
                {
                    "date": s["date"],
                    "code": code,
                    "name": name,
                    "market": MARKET_TAG,
                    "signal_type": s["signal_type"],
                    "signal_category": meta["category"],
                    "signal_name": meta["name"],
                }
            )
        return rows, False
    except Exception as exc:
        print(f"  [오류] {market} {name}: {exc}")
        return [], True


def run(
    *,
    days_back: int = 5,
    skip_telegram: bool = False,
    limit: int | None = None,
    workers: int = DEFAULT_WORKERS,
) -> None:
    target_dates = get_target_calendar_dates(days_back)
    print(f"[코인 스캐너] 대상 일자: {sorted(target_dates)}")

    markets = fetch_krw_markets()
    if limit is not None and limit > 0:
        markets = markets[:limit]
    total = len(markets)
    print(f"[코인 스캐너] KRW 마켓 {total}개")

    all_rows: list[dict] = []
    error_count = 0
    workers = max(1, workers)

    if workers == 1:
        for i, item in enumerate(markets):
            rows, had_error = _scan_one_market(item, target_dates)
            if had_error:
                error_count += 1
            all_rows.extend(rows)
            if (i + 1) % 50 == 0:
                print(f"  진행: {i + 1}/{total}  누적 신호: {len(all_rows)}건")
    else:
        print(f"[코인 스캐너] 병렬 workers={workers}")
        done = 0
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                pool.submit(_scan_one_market, item, target_dates): item
                for item in markets
            }
            for fut in as_completed(futures):
                rows, had_error = fut.result()
                if had_error:
                    error_count += 1
                all_rows.extend(rows)
                done += 1
                if done % 50 == 0:
                    print(f"  진행: {done}/{total}  누적 신호: {len(all_rows)}건")

    print(f"\n[코인 스캐너 완료] 총 신호: {len(all_rows)}건  오류: {error_count}개")

    if all_rows:
        print("[업로드] Supabase signals 테이블에 저장 중...")
        upsert_batch(all_rows)
        print(f"[업로드 완료] {len(all_rows)}건 저장됨")
    else:
        print("[업로드] 저장할 신호 없음")

    if not skip_telegram:
        notify_telegram_for_latest_day(all_rows, target_dates)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="업비트 KRW 코인 매수신호 스캐너")
    parser.add_argument("--days", type=int, default=5, help="최근 N일 (기본 5)")
    parser.add_argument("--no-telegram", action="store_true", help="텔레그램 발송 생략")
    parser.add_argument("--limit", type=int, default=None, help="테스트: 처음 N개 마켓만")
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS, help="병렬 조회 수 (기본 8)")
    args = parser.parse_args()
    try:
        run(days_back=args.days, skip_telegram=args.no_telegram, limit=args.limit, workers=args.workers)
    except KeyboardInterrupt:
        sys.exit(130)
