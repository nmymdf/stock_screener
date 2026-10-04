/// 持股畫面共用：把一筆持股跟最新的行情、市場、產業、推薦結果一起丟進判斷邏輯，
/// 以及狀態的顏色、圖示、數字輸入。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/factors.dart';
import '../core/sources.dart';
import '../data/history_store.dart';
import '../data/holdings_store.dart';
import '../data/longterm_store.dart';
import '../data/stock_industry.dart';
import '../logic/dividend_income.dart';
import '../logic/engine/signals.dart';
import '../logic/holding_eval.dart';
import '../models/holding.dart';

HoldingEval evalFor(BuildContext context, Holding h) {
  final store = context.watch<HistoryStore>();
  final a = store.analysis;
  final report = a?.stock(h.code);
  final industry = industryOf(h.code);
  final regime = a?.today?.regime;
  return evaluateHolding(
    h,
    adjusted: store.seriesOf(h.code),
    raw: store.rawSeriesOf(h.code),
    regime: regime,
    industry: industry,
    industryClass: a?.industry(industry)?.cls,
    newSignal: report?.primary?.hit.strategy.label,
    regimeByDate: a?.regimeByDate,
    taiex: store.taiexByDate,
    drawdownLimit: context.select<HoldingsStore, double>((s) => s.drawdownLimit),
  );
}

/// 長期評分（沒有資料包、或上櫃／ETF 不在範圍是 null）。
LtScore? ltScoreFor(BuildContext context, String code) =>
    context.select<LongTermStore, LtScore?>((s) => s.result?.scoreOf(code));

/// 有長期評分的股票總數（算「前幾 %」用）。
int ltTotal(BuildContext context) => context.select<LongTermStore, int>((s) => s.result?.live.ranked.length ?? 0);

/// 長期提醒：理由破壞或排名掉到後 30%。
String? ltAlert(LtScore? s) => s == null ? null : (s.broken ? '長期理由破壞，考慮換掉' : (s.pct < 0.3 ? '長期總分掉到後 30%' : null));

/// 持有期間估計領到的股利。
List<DividendItem> dividendsFor(BuildContext context, Holding h) {
  final ev = context.select<LongTermStore, List<DivEvent>?>((s) => s.result?.data.dividends.byCode[h.code]);
  if (ev != null && ev.isNotEmpty) return dividendIncome(h, ev);
  return dividendIncome(h, derivedDividends(context.read<HistoryStore>().rawSeriesOf(h.code)));
}

/// 預設持有方式：先看預估持有期間（D1 短線、D2／D3 波段），沒有的話看訊號類型
/// （突破、趨勢延續偏波段；回檔、均值回歸偏短線）。
HoldStyle defaultStyleFor(Strategy? s, {int? duration}) {
  if (s == Strategy.meanReversion) return HoldStyle.short;
  if (duration != null) return duration <= 1 ? HoldStyle.short : HoldStyle.swing;
  return switch (s) {
    Strategy.breakout || Strategy.continuation => HoldStyle.swing,
    Strategy.pullback || Strategy.meanReversion => HoldStyle.short,
    null => HoldStyle.swing,
  };
}

Color stateColor(HoldState s) => switch (s) {
  HoldState.stopLoss => const Color(0xFFD32F2F),
  HoldState.exit => const Color(0xFF1E6FD9),
  HoldState.watch => const Color(0xFFC98A00),
  HoldState.hold => const Color(0xFF2E7D32),
  HoldState.unknown => Colors.grey,
};

IconData stateIcon(HoldState s) => switch (s) {
  HoldState.stopLoss => Icons.dangerous,
  HoldState.exit => Icons.logout,
  HoldState.watch => Icons.warning_amber_rounded,
  HoldState.hold => Icons.check_circle,
  HoldState.unknown => Icons.help_outline,
};

class StateChip extends StatelessWidget {
  final HoldState state;
  final bool big;
  const StateChip(this.state, {super.key, this.big = false});

  @override
  Widget build(BuildContext context) {
    final c = stateColor(state);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 10 : 7, vertical: big ? 4 : 2),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stateIcon(state), size: big ? 18 : 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            state.label,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: big ? 15 : 12),
          ),
        ],
      ),
    );
  }
}

double? parseInput(String s) => double.tryParse(s.replaceAll(',', '').trim());

String moneyTxt(double v) {
  final s = v.abs().round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '${v < 0 ? '−' : (v > 0 ? '+' : '')}$s';
}
