"""Data fetcher and feature engineering for OHLCV CSV data."""
from typing import Optional
import pandas as pd
import numpy as np

class DataFetcher:
    """Load CSV OHLCV data and compute features.

    Expected CSV columns: datetime, open, high, low, close, volume
    """

    def load_csv(self, path: str, datetime_col: str = 'datetime') -> pd.DataFrame:
        df = pd.read_csv(path)
        if datetime_col in df.columns:
            df[datetime_col] = pd.to_datetime(df[datetime_col])
            df = df.set_index(datetime_col).sort_index()
        return df

    def _true_range(self, high: pd.Series, low: pd.Series, close: pd.Series) -> pd.Series:
        tr1 = high - low
        tr2 = (high - close.shift(1)).abs()
        tr3 = (low - close.shift(1)).abs()
        return pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)

    def atr(self, df: pd.DataFrame, length: int = 14) -> pd.Series:
        tr = self._true_range(df['high'], df['low'], df['close'])
        return tr.rolling(length, min_periods=1).mean()

    def rsi(self, series: pd.Series, length: int = 14) -> pd.Series:
        delta = series.diff()
        up = delta.clip(lower=0)
        down = -1 * delta.clip(upper=0)
        ma_up = up.rolling(length, min_periods=1).mean()
        ma_down = down.rolling(length, min_periods=1).mean()
        rs = ma_up / (ma_down + 1e-9)
        return 100 - (100 / (1 + rs))

    def adx(self, df: pd.DataFrame, length: int = 14) -> pd.Series:
        # Simplified ADX calculation
        high = df['high']
        low = df['low']
        close = df['close']
        plus_dm = high.diff()
        minus_dm = -low.diff()
        plus_dm = plus_dm.where((plus_dm > minus_dm) & (plus_dm > 0), 0.0)
        minus_dm = minus_dm.where((minus_dm > plus_dm) & (minus_dm > 0), 0.0)
        tr = self._true_range(high, low, close)
        atr = tr.rolling(length, min_periods=1).mean()
        plus_di = 100 * (plus_dm.rolling(length, min_periods=1).sum() / (atr + 1e-9))
        minus_di = 100 * (minus_dm.rolling(length, min_periods=1).sum() / (atr + 1e-9))
        dx = ( (plus_di - minus_di).abs() / (plus_di + minus_di + 1e-9) ) * 100
        adx = dx.rolling(length, min_periods=1).mean()
        return adx

    def macd(self, series: pd.Series, fast: int = 12, slow: int = 26, signal: int = 9):
        ema_fast = series.ewm(span=fast, adjust=False).mean()
        ema_slow = series.ewm(span=slow, adjust=False).mean()
        macd_line = ema_fast - ema_slow
        signal_line = macd_line.ewm(span=signal, adjust=False).mean()
        return macd_line - signal_line

    def bollinger_width(self, series: pd.Series, length: int = 20, n_std: float = 2.0):
        ma = series.rolling(length, min_periods=1).mean()
        std = series.rolling(length, min_periods=1).std()
        upper = ma + n_std * std
        lower = ma - n_std * std
        return (upper - lower) / (ma + 1e-9)

    def compute_features(self, df: pd.DataFrame) -> pd.DataFrame:
        out = df.copy()
        out['returns'] = out['close'].pct_change()
        out['log_returns'] = np.log(out['close']).diff()
        out['atr_14'] = self.atr(out, 14)
        out['adx_14'] = self.adx(out, 14)
        out['rsi_14'] = self.rsi(out['close'], 14)
        out['macd'] = self.macd(out['close'])
        out['bb_width'] = self.bollinger_width(out['close'], 20)
        out['mom_10'] = out['close'] - out['close'].shift(10)
        out['vol_pct_100'] = out['returns'].rolling(100, min_periods=1).std() * np.sqrt(252)
        out = out.dropna()
        return out


if __name__ == '__main__':
    print('DataFetcher module loaded')
