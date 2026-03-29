"""Analyze backtest results per regime and produce metrics and plots."""
from typing import Dict, Any
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

class BacktestAnalyzer:
    def load_backtest(self, csv_path: str) -> pd.DataFrame:
        df = pd.read_csv(csv_path, parse_dates=['datetime'])
        df = df.set_index('datetime').sort_index()
        return df

    def compute_per_regime_metrics(self, df: pd.DataFrame, regime_labels: pd.Series) -> Dict[Any, Dict[str, float]]:
        # df expected to have 'equity' or 'returns'
        if 'returns' in df.columns:
            returns = df['returns']
        elif 'equity' in df.columns:
            returns = df['equity'].pct_change().fillna(0)
        else:
            raise ValueError('Backtest must contain returns or equity column')
        metrics = {}
        merged = pd.DataFrame({'returns': returns}).join(regime_labels.rename('regime'))
        for r, g in merged.groupby('regime'):
            rts = g['returns']
            if len(rts) == 0:
                continue
            avg = rts.mean()
            vol = rts.std()
            sharpe = (avg / (vol + 1e-9)) * np.sqrt(252)
            down = rts[rts < 0]
            sortino = (avg / (down.std() + 1e-9)) * np.sqrt(252) if len(down) > 0 else np.nan
            cum = (1 + rts).cumprod()
            drawdown = cum.cummax() - cum
            max_dd = drawdown.max()
            win_rate = (rts > 0).mean()
            avg_profit = rts[rts>0].mean() if (rts>0).any() else 0.0
            avg_loss = rts[rts<0].mean() if (rts<0).any() else 0.0
            metrics[r] = {'sharpe': float(sharpe), 'sortino': float(sortino), 'max_dd': float(max_dd), 'win_rate': float(win_rate), 'avg_profit': float(avg_profit), 'avg_loss': float(avg_loss), 'n_trades': int(len(rts))}
        return metrics

    def plot_equity_curve(self, df: pd.DataFrame, regime_labels: pd.Series, save_path: str = None):
        fig, ax = plt.subplots(figsize=(10,6))
        if 'equity' in df.columns:
            equity = df['equity']
        else:
            equity = (1 + df['returns']).cumprod()
        colors = sns.color_palette('tab10', n_colors=len(set(regime_labels)))
        for r in sorted(set(regime_labels)):
            mask = (regime_labels == r)
            ax.plot(equity.index[mask], equity[mask], '.', label=f'regime {r}', color=colors[r % len(colors)])
        ax.set_title('Equity by regime')
        ax.legend()
        if save_path:
            fig.savefig(save_path)
        return fig

    def plot_regime_heatmap(self, df: pd.DataFrame, regime_labels: pd.Series, save_path: str = None):
        merged = pd.DataFrame({'returns': df['returns']}).join(regime_labels.rename('regime'))
        pivot = merged.reset_index().pivot_table(index=merged.index.date, columns='regime', values='returns', aggfunc='mean')
        fig, ax = plt.subplots(figsize=(12,6))
        sns.heatmap(pivot.fillna(0).T, cmap='RdYlGn', center=0, ax=ax)
        ax.set_title('Average returns per day by regime')
        if save_path:
            fig.savefig(save_path)
        return fig

    def compare_strategies(self, strategy_a_df: pd.DataFrame, strategy_b_df: pd.DataFrame, regime_labels: pd.Series) -> Dict:
        # Compare mean returns per regime
        a = strategy_a_df['returns']
        b = strategy_b_df['returns']
        merged = pd.DataFrame({'a': a, 'b': b}).join(regime_labels.rename('regime'))
        results = {}
        for r, g in merged.groupby('regime'):
            results[r] = {'a_mean': float(g['a'].mean()), 'b_mean': float(g['b'].mean()), 'delta': float(g['b'].mean() - g['a'].mean())}
        return results

    def regime_detection_accuracy(self, predicted_regimes: pd.Series, actual_regimes: pd.Series) -> float:
        matched = predicted_regimes.loc[actual_regimes.index] == actual_regimes
        return float(matched.mean())

if __name__ == '__main__':
    print('BacktestAnalyzer loaded')
