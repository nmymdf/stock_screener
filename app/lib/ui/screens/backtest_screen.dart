/// 「回測」：用本機的歷史資料驗證推薦邏輯過去的表現（規格書 §15）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/stock_catalog.dart';
import '../../logic/engine/backtest.dart';
import '../../logic/engine/signals.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/score_widgets.dart';
import '../widgets/sync_status.dart';
import 'stock_report_screen.dart';

class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  final Set<Strategy> _strategies = {...Strategy.values};
  double _slip = 0.1;
  int _timeStop = 10;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final r = store.backtest;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const Text('策略回測', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '把「推薦清單用的同一套規則」套到過去每一天：第 t 天收盤出現訊號、通過否決，就在 t+1 天開盤進場'
          '（開盤超過可接受價就放棄），之後照交易計畫的停損、2R 出一半、保本、移動停利、時間停損出場，'
          '扣掉手續費 0.1425%、證交稅（股票 0.3%／ETF 0.1%）和滑價。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (store.tradingDates.length < 120) ...[
          const SizedBox(height: 8),
          const SyncStatusCard(),
          Text(
            '目前本機只有 ${store.tradingDates.length} 個交易日，回測至少需要 120 天以上才有意義（前 60 天用來暖機指標）。',
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
          ),
        ],
        SectionCard(
          title: '設定',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in Strategy.values)
                    FilterChip(
                      label: Text(s.label),
                      selected: _strategies.contains(s),
                      onSelected: (v) => setState(() => v ? _strategies.add(s) : _strategies.remove(s)),
                    ),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('單邊滑價', style: TextStyle(fontSize: 13))),
                  DropdownButton<double>(
                    value: _slip,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final v in const [0.0, 0.05, 0.1, 0.2, 0.3]) DropdownMenuItem(value: v, child: Text('$v%')),
                    ],
                    onChanged: (v) => setState(() => _slip = v ?? _slip),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('時間停損（幾天沒有 +1R 就出場）', style: TextStyle(fontSize: 13))),
                  DropdownButton<int>(
                    value: _timeStop,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final v in const [5, 10, 15, 20, 30]) DropdownMenuItem(value: v, child: Text('$v 天')),
                    ],
                    onChanged: (v) => setState(() => _timeStop = v ?? _timeStop),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: store.backtesting || _strategies.isEmpty || store.tradingDates.length < 80
                      ? null
                      : () => store.runBacktest(
                          BacktestConfig(strategies: {..._strategies}, slippagePct: _slip, timeStopDays: _timeStop),
                        ),
                  icon: store.backtesting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: Text(store.backtesting ? '回測中…（全市場逐日模擬，約數秒到數十秒）' : '開始回測'),
                ),
              ),
              if (store.backtestError != null)
                Text(store.backtestError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        if (r != null) ..._results(context, r),
      ],
    );
  }

  List<Widget> _results(BuildContext context, BacktestResult r) {
    final o = r.overall;
    if (o.n == 0) {
      return [const SectionCard(child: Text('這段期間沒有任何交易（沒有訊號通過否決，或市場一直處於空頭）。可以抓更長的歷史資料再試。'))];
    }
    String pf(double v) => v.isInfinite ? '∞' : v.toStringAsFixed(2);
    Color? rc(double v) => changeColor(context, v);
    final risk = context.read<HistoryStore>().risk;
    final perTrade = o.avgR * risk.riskPct;
    return [
      SectionCard(
        title: '結果：${r.fromDate} ～ ${r.toDate}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatGrid(
              bare: true,
              stats: [
                ('交易次數', '${o.n}', null),
                ('勝率', '${(o.winRate * 100).toStringAsFixed(1)}%', null),
                ('平均每筆', '${o.avgR >= 0 ? '+' : ''}${o.avgR.toStringAsFixed(2)} R', rc(o.avgR)),
                ('Profit Factor', pf(o.profitFactor), null),
                ('平均盈虧比', pf(o.payoff), null),
                ('最大回撤', '${o.maxDdR.toStringAsFixed(1)} R', null),
                ('最大連敗', '${o.maxConsecLoss} 筆', null),
                ('平均持有', '${o.avgDays.toStringAsFixed(1)} 天', null),
                ('平均報酬', '${o.avgRetPct >= 0 ? '+' : ''}${o.avgRetPct.toStringAsFixed(2)}%', rc(o.avgRetPct)),
              ],
            ),
            const SizedBox(height: 8),
            Bullets([
              '「R」是每筆的初始風險（進場價到停損的距離）。平均每筆 ${o.avgR.toStringAsFixed(2)} R，'
                  '如果照你的設定每筆承擔 ${risk.riskPct}% 資金的風險，平均每筆對資金的影響約 ${perTrade >= 0 ? '+' : ''}${perTrade.toStringAsFixed(3)}%。',
              '勝率不需要很高：盈虧比 ${pf(o.payoff)} 代表賺的時候平均賺 ${o.avgWinR.toStringAsFixed(2)} R、賠的時候平均賠 ${o.avgLossR.abs().toStringAsFixed(2)} R。',
              if (o.profitFactor < 1) '⚠ Profit Factor < 1：這段期間這組規則是虧錢的，不應該照著實盤操作。',
              '訊號 ${r.signals} 次：${r.skippedChase} 次因為隔天開盤超過可接受價（或開盤漲停）而放棄、沒有追價；'
                  '${r.skippedGap} 次因為開盤就跌到停損附近、訊號失效而不進場。',
            ], BulletKind.info),
          ],
        ),
      ),
      SectionCard(
        title: '累積損益（R，依出場日累加）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (r.trades.any((t) => t.openAtEnd))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '有 ${r.trades.where((t) => t.openAtEnd).length} 筆到最後一天還沒出場，以最後收盤價計算、都算在最後一天，'
                  '所以曲線最後可能會突然跳一段——那是還沒實現的損益。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            SimpleChart(
              height: 180,
              yFormat: (v) => v.toStringAsFixed(1),
              series: [
                ChartSeries('累積 R', [for (final e in r.equity) e.$2], Theme.of(context).colorScheme.primary, width: 2),
              ],
              startLabel: r.equity.first.$1,
              endLabel: r.equity.last.$1,
            ),
          ],
        ),
      ),
      SectionCard(
        title: '各策略',
        child: Column(
          children: [
            for (final e in r.byStrategy.entries)
              if (e.value.n > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 108,
                        child: StrategyTag(code: e.key.code, label: e.key.label),
                      ),
                      Expanded(
                        child: Text(
                          '${e.value.n} 筆 · 勝率 ${(e.value.winRate * 100).toStringAsFixed(0)}% · '
                          '平均 ${e.value.avgR.toStringAsFixed(2)} R · PF ${pf(e.value.profitFactor)} · 回撤 ${e.value.maxDdR.toStringAsFixed(1)} R',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 108,
                        child: StrategyTag(code: e.key.code, label: e.key.label, dimmed: true),
                      ),
                      const Text('沒有交易', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
          ],
        ),
      ),
      SectionCard(
        title: '穩健度檢查（§15.2）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Compare('前段 70%（${r.fromDate} 起）', r.firstPart, '後段 30%（${r.splitDate} 起）', r.secondPart),
            Text('參數沒有用這段資料最佳化過；前後兩段結果方向一致，比較不像是巧合。', style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 20),
            _Compare('基本設定', o, '壓力測試', r.stressed),
            Text('壓力測試：滑價 ×2、手續費 ×1.5、晚一天進場。條件變差之後還能接受，策略才算穩健。', style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 20),
            KvRow(
              'Monte Carlo 最大回撤',
              '中位數 ${r.mcDdMedian.toStringAsFixed(1)} R · 95% ${r.mcDd95.toStringAsFixed(1)} R',
              note:
                  '把交易順序隨機打亂 1,000 次：運氣不好時可能遇到的回撤。用它來決定單筆風險——'
                  '例如 95% 回撤 ${r.mcDd95.toStringAsFixed(0)} R × 單筆 ${context.read<HistoryStore>().risk.riskPct}% '
                  '≈ 帳戶回撤 ${(r.mcDd95 * context.read<HistoryStore>().risk.riskPct).toStringAsFixed(1)}%。',
            ),
          ],
        ),
      ),
      SectionCard(
        title: '出場原因',
        child: Column(
          children: [
            for (final e in _reasons(r.trades).entries)
              KvRow(e.key, '${e.value.$1} 筆 · 平均 ${(e.value.$2 / e.value.$1).toStringAsFixed(2)} R'),
          ],
        ),
      ),
      const SectionHeader(left: '最近 40 筆交易'),
      RowList(
        children: [
          for (final t in r.trades.reversed.take(40))
            InfoRow(
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: t.code))),
              title: Row(
                children: [
                  StrategyTag(code: t.strategy.code, label: t.strategy.code),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${t.code} ${kBuiltinStocksByCode[t.code]?.name ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                '${t.entryDate} 進 ${t.entry.toStringAsFixed(2)} → ${t.exitDate} 出 ${t.exit.toStringAsFixed(2)} · ${t.exitReason}',
              ),
              trailingTop: Text(
                '${t.r >= 0 ? '+' : ''}${t.r.toStringAsFixed(2)} R',
                style: TextStyle(color: changeColor(context, t.r)),
              ),
              trailingBottom: Text('${t.retPct >= 0 ? '+' : ''}${t.retPct.toStringAsFixed(1)}%'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      const DisclaimerCard(
        text:
            '回測的限制：這是逐筆訊號統計（每筆固定 1R 風險），不是投資組合模擬——沒有同時持股上限、資金排擠；'
            '還沒有產業、基本面、籌碼分數；歷史資料只有本機抓的天數，樣本不大。過去的結果不代表未來。',
      ),
    ];
  }

  Map<String, (int, double)> _reasons(List<BtTrade> trades) {
    final m = <String, (int, double)>{};
    for (final t in trades) {
      final k = t.openAtEnd
          ? '到資料最後一天仍持有（以最後收盤計）'
          : (t.exitReason.startsWith('2R') ? '2R 先出一半＋剩下移動停利出場' : t.exitReason);
      final v = m[k] ?? (0, 0.0);
      m[k] = (v.$1 + 1, v.$2 + t.r);
    }
    return m;
  }
}

class _Compare extends StatelessWidget {
  final String la, lb;
  final BtStats a, b;
  const _Compare(this.la, this.a, this.lb, this.b);

  @override
  Widget build(BuildContext context) {
    Widget col(String l, BtStats s) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('${s.n} 筆 · 勝率 ${(s.winRate * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
          Text(
            '平均 ${s.avgR >= 0 ? '+' : ''}${s.avgR.toStringAsFixed(2)} R',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: changeColor(context, s.avgR)),
          ),
        ],
      ),
    );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [col(la, a), col(lb, b)]);
  }
}
