# Dynamic Indicator Settings — Research & Planning

## Goal
Build a market-regime-aware trading system that dynamically adjusts indicator weights and parameters based on detected market conditions.

## Current State
- Expert: `Ma_Rsi.mq5` — multi-indicator (MA, BB, RSI, MACD, ADX, ATR) weighted confidence system
- Fixed weights: MA=0.4, BB=0.1, RSI=0.3, MACD=0.2, ADX=0.1 (must sum to 1.0)
- Static parameter inputs (periods, overbought/oversold levels)

## Research Threads

### 1. Market Regime Detection Methods
- Hidden Markov Models (HMM) — most common for market regimes
- Kalman Filters — real-time state estimation
- Volatility regime switching (low/med/high vol based on ATR percentiles)
- Rolling window clustering (K-means on price features)
- Regime detection via market microstructure (trend strength, volume, volatility)

### 2. Academic & Mathematical Foundations
- Research papers on adaptive trading systems
- Proofs of why regime switching improves risk-adjusted returns
- Information theory applied to market regimes (entropy-based detection)
- Control theory for adaptive systems

### 3. Industry Practice
- How Renaissance, Two Sigma, Citadel approach regime detection
- Bridgewater's "risk parity" approach to regime switching
- CTA/CVAR trend-following systems and their regime handling
- Publicly known adaptive strategy implementations

### 4. Dynamic Indicator Adjustment Strategies
- How to adjust indicator weights per regime
- How to adjust indicator parameters (period, thresholds) per regime
- Which indicators work best in which regimes (e.g., momentum in trending, mean-reversion in ranging)
- Smooth transitions vs hard switches between regimes

## Phased Plan

### Phase 1: Regime Detection (Core)
- [ ] Implement ATR-based volatility regime detector (3 buckets: low/mid/high)
- [ ] Add rolling window percentile-based regime classification
- [ ] Add regime persistence filter (avoid flickering)

### Phase 2: Adaptive Weights
- [ ] Define regime-specific weight profiles
- [ ] Smooth transition between weight profiles
- [ ] Expose regime weights as optimizable inputs

### Phase 3: Adaptive Parameters
- [ ] Regime-specific RSI overbought/oversold levels
- [ ] Regime-specific ATR SL/TP multipliers
- [ ] Regime-specific MA period adjustments

### Phase 4: Advanced (Future)
- [ ] HMM-based regime detection
- [ ] ML model for regime prediction
- [ ] Python training pipeline for regime models

## Testing Plan
- Use MT5 Strategy Tester with regime-specific parameter sets
- Walk-forward analysis across different market periods (2020 crash, 2021 bull, 2022 bear, 2023 sideways)
- Compare Sharpe, max drawdown, profit factor across regimes
- Optimize weight profiles per regime using MQL5 optimizer
- Python scripts for post-test analysis and visualization

## Tech Stack
- MQL5 for live trading and backtesting
- Python for data analysis, regime model training, and visualization
- GitHub Issues for tracking features and bugs
