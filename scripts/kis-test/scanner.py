"""
매수신호 스캐너 — KOSPI/KOSDAQ 전 종목(스팩 제외) 기술적 지표 분석 후 Supabase signals 테이블에 저장

지원 신호 유형 (11종):
  추세:   MACD_GOLDEN_CROSS, MA_GOLDEN_CROSS, PRICE_ABOVE_MA20, MA_ALIGNMENT
  모멘텀: RSI_OVERSOLD_EXIT, RSI_50_CROSS, STOCH_GOLDEN_CROSS, CCI_MINUS100_CROSS
  볼린저: BOLL_LOWER_BOUNCE, BOLL_SQUEEZE_BREAKOUT, BOLL_MIDLINE_RECOVERY

사용법:
  pip install -r requirements.txt
  cp .env.example .env          # SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY 입력
  python scanner.py             # 최근 5거래일 신호 저장
  python scanner.py --days 30   # 최근 30거래일 신호 저장 (초기 적재 시)

GitHub Actions:
  이 저장소 루트 .github/workflows/kis-scanner-schedule.yml — 평일 스케줄로
  `python scanner.py --days 10` 실행.
  Actions 시크릿: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, TELEGRAM_BOT_TOKEN
  (선택: KIS_APP_KEY, KIS_APP_SECRET — --source kis 사용 시)
"""

import os
import sys
import time
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
import FinanceDataReader as fdr
import requests
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
KIS_APP_KEY    = os.environ.get("KIS_APP_KEY", "")
KIS_APP_SECRET = os.environ.get("KIS_APP_SECRET", "")
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("오류: .env 파일에 SUPABASE_URL 과 SUPABASE_SERVICE_ROLE_KEY 를 설정해주세요.")
    sys.exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

SIGNAL_DEFS = {
    "MACD_GOLDEN_CROSS":     {"category": "추세",   "name": "MACD 골든크로스"},
    "MA_GOLDEN_CROSS":       {"category": "추세",   "name": "이동평균 골든크로스"},
    "PRICE_ABOVE_MA20":      {"category": "추세",   "name": "20일선 돌파"},
    "MA_ALIGNMENT":          {"category": "추세",   "name": "이동평균 정배열"},
    "RSI_OVERSOLD_EXIT":     {"category": "모멘텀", "name": "RSI 과매도 탈출"},
    "RSI_50_CROSS":          {"category": "모멘텀", "name": "RSI 50선 돌파"},
    "STOCH_GOLDEN_CROSS":    {"category": "모멘텀", "name": "스토캐스틱 골든크로스"},
    "CCI_MINUS100_CROSS":    {"category": "모멘텀", "name": "CCI -100선 돌파"},
    "BOLL_LOWER_BOUNCE":     {"category": "볼린저", "name": "볼린저 하단 반등"},
    "BOLL_SQUEEZE_BREAKOUT": {"category": "볼린저", "name": "볼린저 밴드 상향 돌파"},
    "BOLL_MIDLINE_RECOVERY": {"category": "볼린저", "name": "볼린저 중심선 회복"},
}


# ──────────────────────────────────────────────
# 지표 계산 함수
# ──────────────────────────────────────────────

def calc_rsi(close: pd.Series, period: int = 14) -> pd.Series:
    delta = close.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.ewm(com=period - 1, min_periods=period).mean()
    avg_loss = loss.ewm(com=period - 1, min_periods=period).mean()
    rs = avg_gain / avg_loss.replace(0, float("nan"))
    return 100 - (100 / (1 + rs))


def calc_stoch(df: pd.DataFrame, k: int = 14, d: int = 3):
    low_min = df["Low"].rolling(k).min()
    high_max = df["High"].rolling(k).max()
    denom = (high_max - low_min).replace(0, float("nan"))
    pct_k = 100 * (df["Close"] - low_min) / denom
    pct_d = pct_k.rolling(d).mean()
    return pct_k, pct_d


def calc_cci(df: pd.DataFrame, period: int = 20) -> pd.Series:
    tp = (df["High"] + df["Low"] + df["Close"]) / 3
    ma = tp.rolling(period).mean()
    mad = tp.rolling(period).apply(lambda x: np.mean(np.abs(x - x.mean())), raw=True)
    return (tp - ma) / (0.015 * mad.replace(0, float("nan")))


# ──────────────────────────────────────────────
# 신호 감지
# ──────────────────────────────────────────────

def detect_signals(df: pd.DataFrame, target_dates: set) -> list:
    """
    df(OHLCV)에서 target_dates 에 해당하는 날 발생한 신호를 반환.
    반환값: [{"date": "YYYY-MM-DD", "signal_type": str}, ...]
    """
    if len(df) < 60:
        return []

    close = df["Close"]

    # ── 추세 ──────────────────────────────────
    ema12 = close.ewm(span=12, adjust=False).mean()
    ema26 = close.ewm(span=26, adjust=False).mean()
    macd = ema12 - ema26
    macd_sig = macd.ewm(span=9, adjust=False).mean()

    ma5  = close.rolling(5).mean()
    ma20 = close.rolling(20).mean()
    ma60 = close.rolling(60).mean()

    series_map = {
        "MACD_GOLDEN_CROSS":  (macd.shift(1) < macd_sig.shift(1)) & (macd >= macd_sig),
        "MA_GOLDEN_CROSS":    (ma5.shift(1) < ma20.shift(1)) & (ma5 >= ma20),
        "PRICE_ABOVE_MA20":   (close.shift(1) < ma20.shift(1)) & (close >= ma20),
        # 전일까지 정배열 아니었다가 당일 성립
        "MA_ALIGNMENT":       ~((ma5.shift(1) > ma20.shift(1)) & (ma20.shift(1) > ma60.shift(1)))
                               & (ma5 > ma20) & (ma20 > ma60),
    }

    # ── 모멘텀 ────────────────────────────────
    rsi = calc_rsi(close)
    pk, pd_ = calc_stoch(df)
    cci = calc_cci(df)

    series_map.update({
        "RSI_OVERSOLD_EXIT":  (rsi.shift(1) <= 30) & (rsi > 30),
        "RSI_50_CROSS":       (rsi.shift(1) < 50) & (rsi >= 50),
        # 스토캐스틱 골든크로스 — 과매수(80↑) 구간 제외
        "STOCH_GOLDEN_CROSS": (pk.shift(1) < pd_.shift(1)) & (pk >= pd_) & (pk < 80),
        "CCI_MINUS100_CROSS": (cci.shift(1) < -100) & (cci >= -100),
    })

    # ── 볼린저 밴드 ───────────────────────────
    boll_mid = close.rolling(20).mean()
    boll_std = close.rolling(20).std()
    boll_upper = boll_mid + 2 * boll_std
    boll_lower = boll_mid - 2 * boll_std
    bw = (boll_upper - boll_lower) / boll_mid.replace(0, float("nan"))
    bw_min20 = bw.rolling(20).min()

    series_map.update({
        "BOLL_LOWER_BOUNCE":     (close.shift(1) <= boll_lower.shift(1)) & (close > boll_lower),
        # 밴드 수축(20일 최소치 근처) 상태에서 상단 돌파
        "BOLL_SQUEEZE_BREAKOUT": (bw.shift(1) < bw_min20.shift(1) * 1.05)
                                  & (close.shift(1) < boll_upper.shift(1)) & (close >= boll_upper),
        "BOLL_MIDLINE_RECOVERY": (close.shift(1) < boll_mid.shift(1)) & (close >= boll_mid),
    })

    results = []
    for signal_type, fired in series_map.items():
        for idx in fired[fired].index:
            date_str = str(idx)[:10]
            if date_str in target_dates:
                results.append({"date": date_str, "signal_type": signal_type})

    return results


# ──────────────────────────────────────────────
# 유틸
# ──────────────────────────────────────────────

def get_target_dates(days_back: int) -> set:
    """최근 N 영업일(토·일 제외) 날짜 집합 반환 (오늘 포함)."""
    result = set()
    d = datetime.today()
    count = 0
    while count < days_back:
        if d.weekday() < 5:
            result.add(d.strftime("%Y-%m-%d"))
            count += 1
        d -= timedelta(days=1)
    return result


def upsert_batch(rows: list):
    """50건씩 나눠 upsert — (date, code, signal_type) 기준 중복 무시."""
    chunk_size = 50
    for start in range(0, len(rows), chunk_size):
        batch = rows[start:start + chunk_size]
        supabase.table("signals").upsert(
            batch, on_conflict="date,code,signal_type"
        ).execute()
        print(f"  → upsert {start + 1}~{start + len(batch)}건 완료")


# ──────────────────────────────────────────────
# 텔레그램 알림 (GitHub Actions 일봉 스캔 후)
# ──────────────────────────────────────────────

def get_active_subscribers() -> list[str]:
    """Supabase telegram_subscribers 에서 활성 구독자 chat_id 목록."""
    try:
        result = supabase.table("telegram_subscribers")\
            .select("chat_id")\
            .eq("is_active", True)\
            .execute()
        return [row["chat_id"] for row in result.data]
    except Exception as e:
        print(f"[텔레그램] 구독자 조회 오류: {e}")
        return []


def send_telegram_to_all(message: str, subscribers: list[str]) -> None:
    """활성 구독자 전원에게 메시지 전송."""
    if not TELEGRAM_BOT_TOKEN:
        print("[텔레그램] TELEGRAM_BOT_TOKEN 미설정 — 발송 생략")
        return
    if not subscribers:
        print("[텔레그램] 활성 구독자 없음 — 발송 생략")
        return

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    success = 0
    fail = 0

    for chat_id in subscribers:
        try:
            r = requests.post(url, json={
                "chat_id": chat_id,
                "text": message,
                "parse_mode": "HTML",
            }, timeout=10)
            if r.status_code == 200:
                success += 1
            else:
                err = r.json().get("error_code", 0)
                if err in (403, 400):
                    supabase.table("telegram_subscribers")\
                        .update({"is_active": False})\
                        .eq("chat_id", chat_id)\
                        .execute()
                    print(f"  [텔레그램] 자동 해제: {chat_id} (봇 차단)")
                fail += 1
        except Exception as e:
            print(f"  [텔레그램] 전송 실패 ({chat_id}): {e}")
            fail += 1
        time.sleep(0.05)

    print(f"[텔레그램] 발송 완료 — 성공 {success}명 / 실패 {fail}명")


def send_daily_signal_messages(signals: list, notify_date: str, subscribers: list[str]) -> None:
    """일봉 배치 스캔 결과를 30건씩 나눠 텔레그램 발송."""
    chunk_size = 30

    for idx in range(0, len(signals), chunk_size):
        chunk = signals[idx: idx + chunk_size]
        part_label = f" ({idx // chunk_size + 1}부)" if len(signals) > chunk_size else ""

        lines = [
            f"🚨 <b>매수시그널 {len(signals)}건{part_label}</b>",
            f"📅 {notify_date} 일봉 스캔 (장 마감 후 자동 알림)\n",
        ]

        by_cat: dict[str, list] = {}
        for s in chunk:
            by_cat.setdefault(s["signal_category"], []).append(s)

        for cat, items in by_cat.items():
            lines.append(f"<b>[{cat}]</b>")
            for s in items:
                lines.append(
                    f"  • {s['name']}({s['code']}) "
                    f"<i>{s['signal_name']}</i> [{s['market']}]"
                )
            lines.append("")

        lines.append("⚠️ 투자 판단 및 책임은 본인에게 있습니다.")
        send_telegram_to_all("\n".join(lines), subscribers)
        time.sleep(1)


def notify_telegram_for_latest_day(all_rows: list, target_dates: set) -> None:
    """가장 최근 거래일 시그널만 텔레그램 발송 (과거 일자 재스캔 시 스팸 방지)."""
    if not TELEGRAM_BOT_TOKEN:
        print("[텔레그램] TELEGRAM_BOT_TOKEN 없음 — 발송 생략")
        return
    if not all_rows:
        print("[텔레그램] 발송할 신호 없음")
        return

    notify_date = max(target_dates)
    to_notify = [r for r in all_rows if r["date"] == notify_date]
    subscribers = get_active_subscribers()

    if not subscribers:
        print("[텔레그램] 활성 구독자 없음 — /start 로 먼저 구독 필요")
        return
    if not to_notify:
        print(f"[텔레그램] {notify_date} 신호 없음 — 발송 생략")
        return

    print(f"[텔레그램] {notify_date} 신호 {len(to_notify)}건 → 구독자 {len(subscribers)}명")
    send_daily_signal_messages(to_notify, notify_date, subscribers)


# ──────────────────────────────────────────────
# 메인 실행
# ──────────────────────────────────────────────

def _fetch_fdr(code: str, fetch_start: str) -> pd.DataFrame | None:
    """FinanceDataReader로 OHLCV 조회."""
    df = fdr.DataReader(code, fetch_start)
    if df is None or len(df) < 60:
        return None
    col_map = {}
    for col in df.columns:
        low = col.lower()
        if low == "open":   col_map[col] = "Open"
        elif low == "high": col_map[col] = "High"
        elif low == "low":  col_map[col] = "Low"
        elif low == "close":col_map[col] = "Close"
    df = df.rename(columns=col_map)
    required = {"Open", "High", "Low", "Close"}
    return df if required.issubset(df.columns) else None


def _is_spac_listing(name: str) -> bool:
    """스팩(SPAC) 상장 종목은 매수 시그널 대상에서 제외."""
    raw = str(name or "").strip()
    if not raw:
        return False
    if "스팩" in raw:
        return True
    if "SPAC" in raw.upper():
        return True
    return False


def _fetch_kis(code: str, fetch_start: str) -> pd.DataFrame | None:
    """KIS API로 OHLCV 조회."""
    from kis_fetcher import fetch_ohlcv
    end_date = datetime.today().strftime("%Y-%m-%d")
    df = fetch_ohlcv(code, fetch_start, end_date, KIS_APP_KEY, KIS_APP_SECRET)
    return df if len(df) >= 60 else None


def _scan_one_stock(
    row: pd.Series,
    target_dates: set,
    fetch_start: str,
    source: str,
) -> tuple[list[dict], bool]:
    """단일 종목 스캔. (신호 rows, 오류 여부) 반환."""
    code = str(row["Code"]).strip()
    name = str(row["Name"]).strip()
    market = row["market"]
    try:
        if source == "kis":
            df = _fetch_kis(code, fetch_start)
            time.sleep(0.05)
        else:
            df = _fetch_fdr(code, fetch_start)
        if df is None:
            return [], False
        signals = detect_signals(df, target_dates)
        rows: list[dict] = []
        for s in signals:
            meta = SIGNAL_DEFS[s["signal_type"]]
            rows.append({
                "date":            s["date"],
                "code":            code,
                "name":            name,
                "market":          market,
                "signal_type":     s["signal_type"],
                "signal_category": meta["category"],
                "signal_name":     meta["name"],
            })
        return rows, False
    except Exception:
        return [], True


def run(
    days_back: int = 5,
    sleep_sec: float = 0.2,
    source: str = "fdr",
    skip_telegram: bool = False,
    limit: int | None = None,
    workers: int = 1,
):
    """
    source: "fdr" = FinanceDataReader (기본, 빠름)
            "kis" = KIS API (정확, 느림 — KIS_APP_KEY/SECRET 필요)
    """
    if source == "kis" and (not KIS_APP_KEY or not KIS_APP_SECRET):
        print("오류: KIS API 사용 시 .env 에 KIS_APP_KEY, KIS_APP_SECRET 을 설정해주세요.")
        sys.exit(1)

    target_dates = get_target_dates(days_back)
    fetch_start = (datetime.today() - timedelta(days=400)).strftime("%Y-%m-%d")

    print(f"[스캐너 시작] 데이터 소스: {source.upper()}")
    print(f"[스캐너] 대상 날짜({days_back}거래일): {sorted(target_dates)}")
    print(f"[스캐너] 가격 데이터 조회 시작일: {fetch_start}")

    kospi  = fdr.StockListing("KOSPI")[["Code", "Name"]].copy()
    kosdaq = fdr.StockListing("KOSDAQ")[["Code", "Name"]].copy()
    kospi["market"]  = "KOSPI"
    kosdaq["market"] = "KOSDAQ"
    stocks = pd.concat([kospi, kosdaq], ignore_index=True)
    _before_spac = len(stocks)
    stocks = stocks[~stocks["Name"].astype(str).map(_is_spac_listing)].reset_index(drop=True)
    _excluded = _before_spac - len(stocks)
    if _excluded:
        print(f"[스캐너] 스팩 종목 제외: {_excluded}개")
    if limit is not None and limit > 0:
        stocks = stocks.head(limit).reset_index(drop=True)
        print(f"[스캐너] 테스트 제한: 처음 {limit}개 종목만 스캔")
    total = len(stocks)
    print(f"[스캐너] 스캔 대상 종목: {total}개\n")

    all_rows = []
    error_count = 0
    workers = max(1, workers)

    if workers == 1:
        for i, row in stocks.iterrows():
            rows, had_error = _scan_one_stock(row, target_dates, fetch_start, source)
            if had_error:
                error_count += 1
                if error_count <= 10:
                    code = str(row["Code"]).strip()
                    name = str(row["Name"]).strip()
                    print(f"  [오류] {code} {name}")
            all_rows.extend(rows)
            if (i + 1) % 100 == 0:
                print(f"  진행: {i + 1}/{total}  누적 신호: {len(all_rows)}건")
                if source == "fdr":
                    time.sleep(sleep_sec)
    else:
        print(f"[스캐너] 병렬 workers={workers}")
        done = 0
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                pool.submit(_scan_one_stock, row, target_dates, fetch_start, source): row
                for _, row in stocks.iterrows()
            }
            for fut in as_completed(futures):
                rows, had_error = fut.result()
                if had_error:
                    error_count += 1
                all_rows.extend(rows)
                done += 1
                if done % 100 == 0:
                    print(f"  진행: {done}/{total}  누적 신호: {len(all_rows)}건")

    print(f"\n[스캐너 완료] 총 신호: {len(all_rows)}건  오류 종목: {error_count}개")

    if all_rows:
        print("[업로드] Supabase signals 테이블에 저장 중...")
        upsert_batch(all_rows)
        print(f"[업로드 완료] {len(all_rows)}건 저장됨")
    else:
        print("[업로드] 저장할 신호 없음 (대상 날짜에 신호 발생 종목 없음)")

    if not skip_telegram:
        notify_telegram_for_latest_day(all_rows, target_dates)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="매수신호 스캐너")
    parser.add_argument(
        "--days", type=int, default=5,
        help="최근 N 거래일 신호 저장 (기본: 5, 초기 적재 시 30~60 권장)"
    )
    parser.add_argument(
        "--source", choices=["fdr", "kis"], default="fdr",
        help="가격 데이터 소스: fdr=FinanceDataReader(기본), kis=KIS API"
    )
    parser.add_argument(
        "--no-telegram", action="store_true",
        help="텔레그램 발송 생략 (DB 저장만)"
    )
    parser.add_argument(
        "--limit", type=int, default=None,
        help="테스트용: 처음 N개 종목만 스캔"
    )
    parser.add_argument(
        "--workers", type=int, default=1,
        help="병렬 조회 수 (FDR 기본 1, GitHub Actions에서는 8 권장)"
    )
    args = parser.parse_args()
    run(
        days_back=args.days,
        source=args.source,
        skip_telegram=args.no_telegram,
        limit=args.limit,
        workers=args.workers,
    )
