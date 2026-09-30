/// 資金配置與風險管理（規格書 §11）：每筆部位由「可承受損失」決定，
/// 不是固定買多少金額。
library;

import 'dart:math' as math;

import 'engine/signals.dart';

class RiskSettings {
  final double capital; // 總資金（元）
  final double riskPct; // 單筆最大風險（%），建議 0.25～0.5
  final double maxPositionPct; // 單檔最大曝險（%），建議 8～10
  final double drawdownPct; // 目前帳戶回撤（%），用來自動降低風險
  final double slippagePct; // 回測用的單邊滑價（%）

  const RiskSettings({
    this.capital = 1000000,
    this.riskPct = 0.5,
    this.maxPositionPct = 10,
    this.drawdownPct = 0,
    this.slippagePct = 0.1,
  });

  /// §11.4 Drawdown Control。
  double get drawdownMultiplier => drawdownPct < 5
      ? 1
      : drawdownPct < 10
      ? 0.8
      : drawdownPct < 15
      ? 0.5
      : 0;

  String get drawdownNote => drawdownPct < 5
      ? '回撤 ${drawdownPct.toStringAsFixed(0)}%：正常風險'
      : drawdownPct < 10
      ? '回撤 ${drawdownPct.toStringAsFixed(0)}%：單筆風險 × 0.8'
      : drawdownPct < 15
      ? '回撤 ${drawdownPct.toStringAsFixed(0)}%：單筆風險 × 0.5'
      : '回撤 ${drawdownPct.toStringAsFixed(0)}% 超過 15%：停止新單，重新檢驗策略';

  Map<String, dynamic> toJson() => {
    'capital': capital,
    'riskPct': riskPct,
    'maxPositionPct': maxPositionPct,
    'drawdownPct': drawdownPct,
    'slippagePct': slippagePct,
  };

  static RiskSettings fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return RiskSettings(
      capital: d('capital', 1000000),
      riskPct: d('riskPct', 0.5),
      maxPositionPct: d('maxPositionPct', 10),
      drawdownPct: d('drawdownPct', 0),
      slippagePct: d('slippagePct', 0.1),
    );
  }

  RiskSettings copyWith({
    double? capital,
    double? riskPct,
    double? maxPositionPct,
    double? drawdownPct,
    double? slippagePct,
  }) => RiskSettings(
    capital: capital ?? this.capital,
    riskPct: riskPct ?? this.riskPct,
    maxPositionPct: maxPositionPct ?? this.maxPositionPct,
    drawdownPct: drawdownPct ?? this.drawdownPct,
    slippagePct: slippagePct ?? this.slippagePct,
  );
}

class Sizing {
  final int shares;
  final double riskBudget; // 這筆最多可以虧多少
  final double amount; // 買進金額
  final double riskAmount; // 碰到停損的實際虧損（含滑價估計）
  final bool cappedByExposure; // 是不是被「單檔最大曝險」限制住
  final String note;

  const Sizing(this.shares, this.riskBudget, this.amount, this.riskAmount, this.cappedByExposure, this.note);

  int get lots => shares ~/ 1000;
  int get oddShares => shares % 1000;
}

/// 例：總資金 1,000 萬、單筆風險 0.5% = 5 萬；停損距離 5 元 → 10,000 股，
/// 再依單檔最大曝險和整股／零股調整（§11.1）。
Sizing sizePosition(RiskSettings r, TradePlan p) {
  final budget = r.capital * r.riskPct / 100 * r.drawdownMultiplier;
  final perShare = p.risk + p.entry * r.slippagePct / 100 * 2;
  if (budget <= 0 || perShare <= 0) {
    return Sizing(0, budget, 0, 0, false, r.drawdownMultiplier == 0 ? r.drawdownNote : '停損距離不合理');
  }
  final byRisk = (budget / perShare).floor();
  final byExposure = (r.capital * r.maxPositionPct / 100 / p.entry).floor();
  final shares = math.max(0, math.min(byRisk, byExposure));
  final capped = byExposure < byRisk;
  return Sizing(
    shares,
    budget,
    shares * p.entry,
    shares * perShare,
    capped,
    capped
        ? '依風險可買 ${_fmt(byRisk)} 股，但單檔曝險上限 ${r.maxPositionPct.toStringAsFixed(0)}% 只能買 ${_fmt(byExposure)} 股'
        : '每股風險 ${perShare.toStringAsFixed(2)} 元（停損距離＋來回滑價），可承受 ${_fmt(budget.round())} 元',
  );
}

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
