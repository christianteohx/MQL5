"""
Regime Classifier — LogisticRegression-based volatility regime predictor.

Reads OHLCV bars, extracts 10 features, trains sklearn LogisticRegression
(multinomial) to predict LOW / MID / HIGH regime, exports predictions.csv.
"""

import argparse
import os
import warnings
from typing import Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _atr(high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14) -> pd.Series:
    tr1 = high - low
    tr2 = np.abs(high - close.shift(1))
    tr3 = np.abs(low - close.shift(1))
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    return tr.rolling(window=period).mean()


def _rsi(series: pd.Series, period: int = 14) -> pd.Series:
    delta = series.diff()
    gain = delta.where(delta > 0, 0.0)
    loss = (-delta).where(delta < 0, 0.0)
    avg_gain = gain.rolling(window=period).mean()
    avg_loss = loss.rolling(window=period).mean()
    rs = avg_gain / avg_loss.replace(0, np.nan)
    return 100 - (100 / (1 + rs))


def _ema(series: pd.Series, span: int) -> pd.Series:
    return series.ewm(span=span, adjust=False).mean()


def _percentile_rank(series: pd.Series, window: int) -> pd.Series:
    """Return the percentile rank of the current value within a rolling window."""
    def _rank(window_vals):
        v = window_vals.iloc[-1]
        return (window_vals < v).sum() / len(window_vals)
    return series.rolling(window=window).apply(_rank, raw=False)


def _zscore(series: pd.Series, window: int) -> pd.Series:
    roll = series.rolling(window=window)
    mean = roll.mean()
    std = roll.std().replace(0, np.nan)
    return (series - mean) / std


# ---------------------------------------------------------------------------
# Feature extraction
# ---------------------------------------------------------------------------

def extract_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Derive 10 features from OHLCV DataFrame.

    Requires columns: high, low, close, volume.
    Returns DataFrame with 10 z-score-normalised features (NaNs dropped).
    """
    high = df["high"]
    low = df["low"]
    close = df["close"]
    volume = df["volume"]

    n = len(df)
    Z_WINDOW = 100          # z-score lookback
    ATR_PERIOD = 14
    RSI_PERIOD = 14
    RET_WINDOW = 20
    MOMENTUM_WINDOW = 5
    EMA20_SPAN = 20
    EMA50_SPAN = 50

    # Precompute EMA once
    ema20 = _ema(close, EMA20_SPAN)
    ema50 = _ema(close, EMA50_SPAN)

    features = pd.DataFrame(index=df.index)

    # 1. ATR z-score
    atr = _atr(high, low, close, ATR_PERIOD)
    features["atr_zscore"] = _zscore(atr, Z_WINDOW)

    # 2. RSI z-score
    rsi = _rsi(close, RSI_PERIOD)
    features["rsi_zscore"] = _zscore(rsi, Z_WINDOW)

    # 3. Return std z-score (20-bar rolling std of returns)
    returns = close.pct_change()
    features["ret_std_zscore"] = _zscore(returns.rolling(RET_WINDOW).std(), Z_WINDOW)

    # 4. Volume change z-score
    vol_chg = volume.pct_change()
    features["vol_chg_zscore"] = _zscore(vol_chg, Z_WINDOW)

    # 5. High-Low range z-score
    hl_range = high - low
    features["hl_range_zscore"] = _zscore(hl_range, Z_WINDOW)

    # 6. Close vs 20 EMA deviation z-score
    close_ema20_dev = (close - ema20) / close
    features["close_ema20_dev_zscore"] = _zscore(close_ema20_dev, Z_WINDOW)

    # 7. 5-bar momentum z-score
    momentum = close.pct_change(MOMENTUM_WINDOW)
    features["momentum_5_zscore"] = _zscore(momentum, Z_WINDOW)

    # 8. ATR percentile rank (0–1, bounded — not z-scored)
    features["atr_pct_rank"] = _percentile_rank(atr, Z_WINDOW)

    # 9. RSI percentile rank
    features["rsi_pct_rank"] = _percentile_rank(rsi, Z_WINDOW)

    # 10. Trend alignment (0, 1, 2)
    trend = ((close > ema20).astype(int) + (close > ema50).astype(int))
    features["trend_alignment"] = trend

    return features.dropna()


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------

def train_logistic_regression(
    features: pd.DataFrame, labels: pd.Series, C: float = 1.0
) -> Tuple[LogisticRegression, StandardScaler]:
    """
    Train a multinomial LogisticRegression on feature/label arrays.

    Parameters
    ----------
    features : pd.DataFrame — shape (N, 10), z-score normalised
    labels   : pd.Series    — "LOW" / "MID" / "HIGH"
    C        : float        — regularisation strength (higher = less regularised)

    Returns
    -------
    (model, scaler) — scaler fits to features for use in prediction
    """
    scaler = StandardScaler()
    X = scaler.fit_transform(features.values)
    y = labels.values

    model = LogisticRegression(
        multi_class="multinomial",
        solver="lbfgs",
        max_iter=1000,
        C=C,
        random_state=42,
    )
    model.fit(X, y)

    return model, scaler


# ---------------------------------------------------------------------------
# Prediction
# ---------------------------------------------------------------------------

LABEL_MAP = {"LOW": 0, "MID": 1, "HIGH": 2}
REV_LABEL_MAP = {0: "LOW", 1: "MID", 2: "HIGH"}


def predict_regime(
    model: LogisticRegression, scaler: StandardScaler, features: pd.DataFrame
) -> Tuple[pd.Series, pd.Series]:
    """
    Predict regime and confidence for each row in features.

    Parameters
    ----------
    model  : trained LogisticRegression
    scaler : fitted StandardScaler
    features : pd.DataFrame — (N, 10)

    Returns
    -------
    (predictions: pd.Series, confidence: pd.Series)
      predictions — "LOW" / "MID" / "HIGH"
      confidence  — max softmax probability (0.0 – 1.0)
    """
    X = scaler.transform(features.values)
    proba = model.predict_proba(X)
    pred_idx = np.argmax(proba, axis=1)
    predictions = pd.Series([REV_LABEL_MAP[i] for i in pred_idx], index=features.index)
    confidence = pd.Series(np.max(proba, axis=1), index=features.index)
    return predictions, confidence


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export_predictions(
    bar_times: pd.DatetimeIndex,
    symbols: pd.Series,
    predictions: pd.Series,
    confidence: pd.Series,
    output_path: str,
) -> None:
    """
    Write predictions to CSV.

    Columns: bar_time, symbol, regime_pred, confidence
    """
    out = pd.DataFrame({
        "bar_time": bar_times.strftime("%Y-%m-%d %H:%M:%S"),
        "symbol": symbols.values,
        "regime_pred": predictions.values,
        "confidence": confidence.values.round(4),
    })
    out.to_csv(output_path, index=False)
    print(f"[regime_classifier] Wrote {len(out)} rows → {output_path}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Regime Classifier — LogisticRegression pipeline")
    p.add_argument("--symbol", default="EURUSD")
    p.add_argument("--timeframe", default="H1")
    p.add_argument("--bars", type=int, default=500,
                   help="Number of bars to fetch for training + prediction")
    p.add_argument("--output", default="predictions.csv")
    p.add_argument("--C", type=float, default=1.0)
    return p


if __name__ == "__main__":
    from data_fetcher import fetch_ohlcv
    from label_generator import generate_labels

    parser = build_parser()
    args = parser.parse_args()

    warnings.filterwarnings("ignore", category=FutureWarning)

    print(f"[regime_classifier] Fetching {args.bars} {args.timeframe} bars for {args.symbol}…")
    df = fetch_ohlcv(args.symbol, args.timeframe, n_bars=args.bars)

    print("[regime_classifier] Generating labels…")
    labels_df = generate_labels(df)

    print("[regime_classifier] Extracting features…")
    features = extract_features(df)

    # Align features with labels (both dropna independently)
    common_idx = features.index.intersection(labels_df.index)
    features_aligned = features.loc[common_idx]
    labels_aligned = labels_df.loc[common_idx, "regime_label"]

    print(f"[regime_classifier] Training on {len(features_aligned)} aligned samples…")
    model, scaler = train_logistic_regression(features_aligned, labels_aligned, C=args.C)

    print("[regime_classifier] Predicting…")
    predictions, confidence = predict_regime(model, scaler, features_aligned)

    bar_times = features_aligned.index
    symbols = pd.Series(args.symbol, index=common_idx)
    export_predictions(bar_times, symbols, predictions, confidence, args.output)

    preview = pd.DataFrame({
        'bar_time': bar_times[-5:].strftime('%Y-%m-%d %H:%M'),
        'regime': predictions.values[-5:],
        'conf': confidence.values[-5:].round(3),
    })
    print(f"\nLast 5 predictions:\n{preview}")
