"""
Data Fetcher — OHLCV data retrieval for regime pipeline.

Fetches bar data from MetaTrader 5 terminal via Python FX bridge.
"""

import pandas as pd
from datetime import datetime
import time


def fetch_ohlcv(symbol: str, timeframe: str, n_bars: int = 500) -> pd.DataFrame:
    """
    Fetch OHLCV bars for a given symbol and timeframe.

    Parameters
    ----------
    symbol : str
        e.g. "EURUSD", "GBPUSD"
    timeframe : str
        e.g. "M1", "M5", "M15", "H1", "H4", "D1"
    n_bars : int
        Number of bars to fetch.

    Returns
    -------
    pd.DataFrame
        Indexed by bar_time (UTC), columns: open, high, low, close, volume, symbol.
    """
    # ------------------------------------------------------------------
    # Placeholder: MT5 bridge not yet implemented.
    # In production this calls into the MQL5 Python FX bridge (mt5bared).
    # ------------------------------------------------------------------

    periods = {
        "M1": 1, "M5": 5, "M15": 15, "M30": 30,
        "H1": 60, "H4": 240, "D1": 1440,
    }
    period = periods.get(timeframe.upper(), 60)

    # Simulated data for development — replace with mt5bared call
    np = __import__("numpy")
    n = min(n_bars, 500)
    now = int(time.time())
    bars_per_day = {
        "M1": 1440, "M5": 288, "M15": 96, "M30": 48,
        "H1": 24, "H4": 6, "D1": 1,
    }
    bars_day = bars_per_day.get(timeframe.upper(), 24)
    start_ts = now - (n * bars_day * 60)

    dates = pd.date_range(end=datetime.utcnow(), periods=n, freq=f"{bars_day}min" if bars_day < 60 else "h")

    rng = np.random.default_rng(seed=42)
    base = 1.08 if "EUR" in symbol else 1.25
    spreads = rng.exponential(scale=0.0002, size=n)
    open_prices = base + rng.normal(0, 0.0005, n)
    close_prices = open_prices + rng.normal(0, 0.0003, n)
    high_prices = np.maximum(open_prices, close_prices) + np.abs(rng.normal(0, 0.0002, n))
    low_prices = np.minimum(open_prices, close_prices) - np.abs(rng.normal(0, 0.0002, n))
    volumes = rng.integers(1000, 10000, n).astype(float)

    df = pd.DataFrame({
        "open": open_prices,
        "high": high_prices,
        "low": low_prices,
        "close": close_prices,
        "volume": volumes,
        "symbol": symbol,
    }, index=pd.DatetimeIndex(dates, name="bar_time"))
    df.index = df.index.tz_localize(None)

    return df


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--symbol", default="EURUSD")
    parser.add_argument("--timeframe", default="H1")
    parser.add_argument("--bars", type=int, default=500)
    args = parser.parse_args()

    df = fetch_ohlcv(args.symbol, args.timeframe, n_bars=args.bars)
    print(df.tail())
