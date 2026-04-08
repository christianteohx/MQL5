"""
ATR Percentile Label Generator

Generates LOW/MID/HIGH volatility regime labels based on ATR percentile ranks.
"""

import pandas as pd
import numpy as np


def compute_atr(high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14) -> pd.Series:
    """Compute Average True Range."""
    tr1 = high - low
    tr2 = np.abs(high - close.shift(1))
    tr3 = np.abs(low - close.shift(1))
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    atr = tr.rolling(window=period).mean()
    return atr


def compute_atr_percentile_rank(
    atr: pd.Series, lookback: int = 100, current_idx: int = -1
) -> float:
    """
    Compute the percentile rank of the current ATR against a lookback window.
    Returns a value between 0.0 and 1.0.
    """
    if len(atr) < lookback:
        return 0.5  # insufficient data, return mid
    window = atr.iloc[current_idx - lookback : current_idx]
    current = atr.iloc[current_idx]
    rank = (window < current).sum() / len(window)
    return rank


def label_regime_by_percentile(
    atr_percentile: float, low_thresh: float = 0.33, high_thresh: float = 0.67
) -> str:
    """Map an ATR percentile rank to a regime label."""
    if atr_percentile < low_thresh:
        return "LOW"
    elif atr_percentile < high_thresh:
        return "MID"
    else:
        return "HIGH"


def generate_labels(
    df: pd.DataFrame,
    period: int = 14,
    lookback: int = 100,
    low_thresh: float = 0.33,
    high_thresh: float = 0.67,
) -> pd.DataFrame:
    """
    Generate regime labels for a DataFrame with high, low, close columns.

    Parameters
    ----------
    df : pd.DataFrame
        Must contain high, low, close columns (and optionally volume).
    period : int
        ATR period (default 14).
    lookback : int
        Lookback window for percentile rank (default 100).
    low_thresh : float
        Percentile threshold below which regime is LOW.
    high_thresh : float
        Percentile threshold above which regime is HIGH.

    Returns
    -------
    pd.DataFrame
        With columns: bar_time, symbol, atr, atr_percentile, regime_label.
    """
    high = df["high"]
    low = df["low"]
    close = df["close"]

    atr = compute_atr(high, low, close, period=period)
    atr_percentile = atr.rolling(window=lookback).apply(
        lambda w: (w < w.iloc[-1]).sum() / len(w), raw=False
    )

    regime_label = atr_percentile.apply(
        lambda x: label_regime_by_percentile(x, low_thresh, high_thresh)
        if pd.notna(x)
        else np.nan
    )

    result = pd.DataFrame({
        "bar_time": df.index,
        "symbol": df.get("symbol", "UNKNOWN"),
        "atr": atr,
        "atr_percentile": atr_percentile,
        "regime_label": regime_label,
    })

    return result.dropna(subset=["regime_label"])


if __name__ == "__main__":
    import argparse
    from data_fetcher import fetch_ohlcv

    parser = argparse.ArgumentParser(description="Generate ATR percentile regime labels")
    parser.add_argument("--symbol", default="EURUSD")
    parser.add_argument("--timeframe", default="H1")
    parser.add_argument("--bars", type=int, default=500)
    args = parser.parse_args()

    df = fetch_ohlcv(args.symbol, args.timeframe, n_bars=args.bars)
    labels = generate_labels(df)
    print(labels.tail(10))
