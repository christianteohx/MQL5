#!/usr/bin/env python3
"""Trade log backtest analyzer for Greg EA.

Expected CSV columns:
  OpenTime, CloseTime, Direction, Pips, Profit, Regime, SignalType, DrawdownPct

Usage:
  python backtest_analyzer.py trades.csv --text
  python backtest_analyzer.py trades.csv --json
  python backtest_analyzer.py trades.csv --text --json
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List


REQUIRED_COLUMNS = {
    "OpenTime",
    "CloseTime",
    "Direction",
    "Pips",
    "Profit",
    "Regime",
    "SignalType",
    "DrawdownPct",
}

REGIME_ORDER = ["LOW", "MID", "HIGH"]


def _to_float(value: str, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def load_trades(csv_path: Path) -> List[Dict[str, Any]]:
    with csv_path.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise ValueError("CSV appears to have no header row")

        missing = REQUIRED_COLUMNS.difference(reader.fieldnames)
        if missing:
            raise ValueError(f"Missing required columns: {sorted(missing)}")

        rows: List[Dict[str, Any]] = []
        for r in reader:
            rows.append(
                {
                    "OpenTime": r.get("OpenTime", ""),
                    "CloseTime": r.get("CloseTime", ""),
                    "Direction": r.get("Direction", ""),
                    "Pips": _to_float(r.get("Pips")),
                    "Profit": _to_float(r.get("Profit")),
                    "Regime": (r.get("Regime") or "UNKNOWN").strip().upper(),
                    "SignalType": (r.get("SignalType") or "UNKNOWN").strip(),
                    "DrawdownPct": _to_float(r.get("DrawdownPct")),
                }
            )
    return rows


def _signal_stats(trades: List[Dict[str, Any]]) -> Dict[str, Dict[str, float]]:
    by_signal: Dict[str, List[float]] = defaultdict(list)
    for t in trades:
        by_signal[t["SignalType"]].append(t["Profit"])

    out: Dict[str, Dict[str, float]] = {}
    for signal, profits in by_signal.items():
        n = len(profits)
        wins = sum(1 for p in profits if p > 0)
        out[signal] = {
            "trades": n,
            "net_profit": sum(profits),
            "win_rate": (wins / n) if n else 0.0,
            "avg_profit": (sum(profits) / n) if n else 0.0,
        }
    return out


def analyze(trades: List[Dict[str, Any]]) -> Dict[str, Any]:
    total = len(trades)
    profits = [t["Profit"] for t in trades]
    pips = [t["Pips"] for t in trades]

    wins = [p for p in profits if p > 0]
    losses = [p for p in profits if p < 0]

    total_profit = sum(profits)
    gross_profit = sum(wins)
    gross_loss_abs = abs(sum(losses))

    win_rate = (len(wins) / total) if total else 0.0
    profit_factor = (gross_profit / gross_loss_abs) if gross_loss_abs > 0 else (math.inf if gross_profit > 0 else 0.0)

    avg_pips = statistics.mean(pips) if pips else 0.0
    std_pips = statistics.stdev(pips) if len(pips) > 1 else 0.0
    sharpe_like = (avg_pips / std_pips) if std_pips > 0 else 0.0

    max_drawdown = max((t["DrawdownPct"] for t in trades), default=0.0)
    expectancy = (total_profit / total) if total else 0.0

    regime_groups: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for t in trades:
        regime_groups[t["Regime"]].append(t)

    regime_breakdown: Dict[str, Any] = {}
    for regime in REGIME_ORDER + sorted(r for r in regime_groups.keys() if r not in REGIME_ORDER):
        group = regime_groups.get(regime, [])
        if not group:
            continue

        gp = [x["Profit"] for x in group]
        gpi = [x["Pips"] for x in group]
        gwins = sum(1 for p in gp if p > 0)

        signal_stats = _signal_stats(group)
        best_signal = None
        worst_signal = None
        if signal_stats:
            ranked = sorted(signal_stats.items(), key=lambda kv: kv[1]["avg_profit"], reverse=True)
            best_signal = {"name": ranked[0][0], **ranked[0][1]}
            worst_signal = {"name": ranked[-1][0], **ranked[-1][1]}

        regime_breakdown[regime] = {
            "trades": len(group),
            "win_rate": (gwins / len(group)) if group else 0.0,
            "avg_profit": (sum(gp) / len(group)) if group else 0.0,
            "avg_pips": (sum(gpi) / len(group)) if group else 0.0,
            "best_signal_type": best_signal,
            "worst_signal_type": worst_signal,
            "signal_stats": signal_stats,
        }

    # Simple ASCII equity curve from cumulative profit
    curve = []
    running = 0.0
    for p in profits:
        running += p
        curve.append(running)

    return {
        "overall": {
            "total_trades": total,
            "win_rate": win_rate,
            "net_profit": total_profit,
            "gross_profit": gross_profit,
            "gross_loss_abs": gross_loss_abs,
            "profit_factor": profit_factor,
            "avg_pips": avg_pips,
            "std_pips": std_pips,
            "sharpe_like": sharpe_like,
            "max_drawdown_pct": max_drawdown,
            "expectancy_per_trade": expectancy,
        },
        "regime_breakdown": regime_breakdown,
        "equity_curve": {
            "points": curve,
            "ascii": render_ascii_curve(curve),
        },
    }


def _pct(x: float) -> str:
    return f"{x * 100:.2f}%"


def render_ascii_curve(curve: List[float], width: int = 60, height: int = 10) -> str:
    if not curve:
        return "(no trades)"

    if len(curve) > width:
        # downsample by bucket averaging
        step = len(curve) / width
        sampled = []
        for i in range(width):
            start = int(i * step)
            end = max(start + 1, int((i + 1) * step))
            bucket = curve[start:end]
            sampled.append(sum(bucket) / len(bucket))
        data = sampled
    else:
        data = curve

    low = min(data)
    high = max(data)
    span = high - low
    if span == 0:
        span = 1.0

    rows = [[" " for _ in range(len(data))] for _ in range(height)]
    for x, v in enumerate(data):
        y = int((v - low) / span * (height - 1))
        row = (height - 1) - y
        rows[row][x] = "*"

    out = ["".join(r) for r in rows]
    out.append(f"low={low:.2f} high={high:.2f} end={data[-1]:.2f}")
    return "\n".join(out)


def format_text(summary: Dict[str, Any]) -> str:
    o = summary["overall"]
    lines = []
    lines.append("=== Backtest Performance Summary ===")
    lines.append(f"Total trades      : {o['total_trades']}")
    lines.append(f"Win rate          : {_pct(o['win_rate'])}")
    lines.append(f"Net profit        : {o['net_profit']:.2f}")
    lines.append(f"Profit factor     : {o['profit_factor']:.4f}" if math.isfinite(o["profit_factor"]) else "Profit factor     : inf")
    lines.append(f"Sharpe-like (pips): {o['sharpe_like']:.4f}")
    lines.append(f"Max drawdown %    : {o['max_drawdown_pct']:.2f}")
    lines.append(f"Expectancy/trade  : {o['expectancy_per_trade']:.4f}")
    lines.append("")

    lines.append("=== Regime Breakdown ===")
    for regime in REGIME_ORDER + [r for r in summary["regime_breakdown"].keys() if r not in REGIME_ORDER]:
        stats = summary["regime_breakdown"].get(regime)
        if not stats:
            continue
        lines.append(f"[{regime}] trades={stats['trades']} win={_pct(stats['win_rate'])} avg_profit={stats['avg_profit']:.4f} avg_pips={stats['avg_pips']:.4f}")
        best = stats.get("best_signal_type")
        worst = stats.get("worst_signal_type")
        if best:
            lines.append(f"  best signal : {best['name']} (avg_profit={best['avg_profit']:.4f}, win={_pct(best['win_rate'])}, n={best['trades']})")
        if worst:
            lines.append(f"  worst signal: {worst['name']} (avg_profit={worst['avg_profit']:.4f}, win={_pct(worst['win_rate'])}, n={worst['trades']})")

    lines.append("")
    lines.append("=== Equity Curve (ASCII) ===")
    lines.append(summary["equity_curve"]["ascii"])
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Analyze Greg EA trade log CSV")
    p.add_argument("csv_path", type=Path, help="Path to trade log CSV")
    p.add_argument("--text", action="store_true", help="Print text summary")
    p.add_argument("--json", action="store_true", help="Print JSON summary")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if not args.text and not args.json:
        args.text = True

    trades = load_trades(args.csv_path)
    summary = analyze(trades)

    if args.text:
        print(format_text(summary))
    if args.json:
        print(json.dumps(summary, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
