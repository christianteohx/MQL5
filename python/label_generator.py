"""Generate regime labels using ATR percentiles, ADX thresholds, combined labels, and HMM."""
from typing import Optional
import numpy as np
import pandas as pd
from hmmlearn.hmm import GaussianHMM

class RegimeLabeler:
    def atr_percentile_labels(self, atr_series: pd.Series, lookback: int = 100, low: float = 0.33, high: float = 0.66) -> pd.Series:
        vals = atr_series.copy()
        roll = vals.rolling(lookback, min_periods=1)
        low_th = roll.quantile(low)
        high_th = roll.quantile(high)
        labels = pd.Series(index=vals.index, dtype=int)
        labels[vals <= low_th] = 0
        labels[(vals > low_th) & (vals <= high_th)] = 1
        labels[vals > high_th] = 2
        return labels

    def adx_labels(self, adx_series: pd.Series, high_thresh: float = 28.0, low_thresh: float = 20.0) -> pd.Series:
        s = adx_series.copy()
        labels = pd.Series(index=s.index, dtype=int)
        labels[s <= low_thresh] = 0
        labels[(s > low_thresh) & (s <= high_thresh)] = 1
        labels[s > high_thresh] = 2
        return labels

    def combined_labels(self, atr_labels: pd.Series, adx_labels: pd.Series) -> pd.Series:
        # Combine into 0..8 (3x3)
        return (atr_labels * 3 + adx_labels).astype(int)

    def hmm_labels(self, features: pd.DataFrame, n_states: int = 3, cov_type: str = 'full', random_state: int = 42) -> pd.Series:
        # Select numerical columns
        X = features.select_dtypes(include=[np.number]).fillna(0).values
        model = GaussianHMM(n_components=n_states, covariance_type=cov_type, n_iter=100, random_state=random_state)
        model.fit(X)
        states = model.predict(X)
        return pd.Series(states, index=features.index)

if __name__ == '__main__':
    print('RegimeLabeler loaded')
