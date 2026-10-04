/// 「回測」：用本機的歷史資料驗證推薦邏輯過去的表現（規格書 §15）。
///
/// 畫面分三段：回測怎麼做（重點流程與名詞）→ 設定（策略、期間、滑價、
/// 時間停損、每筆風險金額）→ 結果（白話結論、以元計算的數字、累積損益、
/// 各策略／各市場狀態、穩健度檢查、出場原因、交易明細）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/stock_catalog.dart';
import '../../logic/engine/backtest.dart';
import '../../logic/engine/market_engine.dart';
import '../../logic/engine/signals.dart';
import '../format.dart';
import '../layout.dart';
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
  int _years = 0; // 0 = 本機全部資料
  double _riskMoney = 10000; // 每筆碰到停損虧多少元（只用來把 R 換成元）

  String? _startDate(HistoryStore store) {
    if (_years == 0 || store.latestDate == null) return null;
    final d = DateTime.parse(store.latestDate!);
    return ymd(DateTime(d.year - _years, d.month, d.day));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final r = store.backtest;
    final days = store.tradingDates.length;
    final span = days == 0 ? '' : '${store.tradingDates.first} ～ ${store.tradingDates.last}（$days 個交易日）';
    return ListView(
      padding: pagePadding(context),
      children: [
        const PageHeader(icon: Icons.science, title: '策略回測', subtitle: '把「推薦用的同一套規則」套到過去每一天，看照做的話會怎樣'),
        _HowItWorks(expanded: r == null),
        if (days < 120) ...[
          const SyncStatusCard(),
          Text(
            '目前本機只有 $days 個交易日，回測至少需要 120 天以上才有意義（前 60 天用來暖機指標）。',
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
          ),
        ],
        SectionCard(
          title: '設定',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本機資料：$span', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              const Text('要測哪些策略', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
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
              const SizedBox(height: 10),
              const Text('回測期間', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (y, l) in const [(0, '本機全部資料'), (1, '最近 1 年'), (2, '最近 2 年')])
                    ChoiceChip(label: Text(l), selected: _years == y, onSelected: (_) => setState(() => _years = y)),
                  if (days < 480)
                    TextButton.icon(
                      onPressed: store.syncing ? null : () => store.extendHistory(800),
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(store.syncing ? '下載中…' : '抓滿 2 年資料'),
                    ),
                ],
              ),
              if (_years == 2 && days < 480)
                Text(
                  '本機資料還不到 2 年，回測會從最早的資料開始。按「抓滿 2 年資料」在背景補抓（約 20 分鐘，抓完自動重新分析）。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 10),
              const Text('換算成金額：每筆碰到停損虧', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final v in const [5000.0, 10000.0, 20000.0, 50000.0])
                    ChoiceChip(
                      label: Text('${f0(v)} 元'),
                      selected: _riskMoney == v,
                      onSelected: (_) => setState(() => _riskMoney = v),
                    ),
                ],
              ),
              Text(
                '只是把 R 換算成元，方便理解：例如選 1 萬元，代表每一筆如果照計畫停損就虧 1 萬元；結果可以直接改，不用重跑。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(child: Text('單邊滑價（成交價比預期差多少）', style: TextStyle(fontSize: 13))),
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
                  onPressed: store.backtesting || _strategies.isEmpty || days < 80
                      ? null
                      : () => store.runBacktest(
                          BacktestConfig(
                            strategies: {..._strategies},
                            slippagePct: _slip,
                            timeStopDays: _timeStop,
                            startDate: _startDate(store),
                          ),
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

  String _money(double r) {
    final v = r * _riskMoney;
    return '${v >= 0 ? '+' : '−'}${f0(v.abs())} 元';
  }

  List<Widget> _results(BuildContext context, BacktestResult r) {
    final o = r.overall;
    if (o.n == 0) {
      return [const SectionCard(child: Text('這段期間沒有任何交易（沒有訊號通過否決，或市場一直處於空頭）。可以抓更長的歷史資料再試。'))];
    }
    String pf(double v) => v.isInfinite ? '∞' : v.toStringAsFixed(2);
    Color? rc(double v) => changeColor(context, v);
    final small = Theme.of(context).textTheme.bodySmall;
    return [
      _Verdict(r: r, riskMoney: _riskMoney),
      SectionCard(
        title: '重點數字',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Kpi('交易次數', '${o.n} 筆', '平均持有 ${o.avgDays.toStringAsFixed(1)} 天'),
                _Kpi('勝率', '${(o.winRate * 100).toStringAsFixed(0)}%', '每 10 筆約 ${(o.winRate * 10).round()} 筆賺錢'),
                _Kpi(
                  '平均每筆',
                  _money(o.avgR),
                  '${o.avgR >= 0 ? '+' : ''}${o.avgR.toStringAsFixed(2)} R',
                  color: rc(o.avgR),
                ),
                _Kpi(
                  '全部加總',
                  _money(o.totalR),
                  '${o.totalR >= 0 ? '+' : ''}${o.totalR.toStringAsFixed(1)} R',
                  color: rc(o.totalR),
                ),
                _Kpi('賺的時候平均', _money(o.avgWinR), '賠的時候平均 ${_money(o.avgLossR)}'),
                _Kpi('Profit Factor', pf(o.profitFactor), '總賺 ÷ 總賠，> 1.3 算不錯'),
                _Kpi('最大回撤', _money(-o.maxDdR), '帳面從高點最多回落'),
                _Kpi('最多連虧', '${o.maxConsecLoss} 筆', '要撐得過這種連敗'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '訊號 ${r.signals} 次：${r.skippedChase} 次因為隔天開盤超過可接受價（或開盤漲停）而放棄、沒有追價；'
              '${r.skippedGap} 次因為開盤就跌到停損附近、訊號失效而不進場。',
              style: small,
            ),
          ],
        ),
      ),
      SectionCard(
        title: '累積損益（依出場日累加）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('怎麼看：線一路往右上走、回落不深，代表規則穩定；大起大落代表要承受很大的心理壓力。', style: small),
            if (r.trades.any((t) => t.openAtEnd))
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text(
                  '有 ${r.trades.where((t) => t.openAtEnd).length} 筆到最後一天還沒出場，以最後收盤價計算、都算在最後一天，'
                  '所以曲線最後可能會突然跳一段——那是還沒實現的損益。',
                  style: small,
                ),
              ),
            SimpleChart(
              height: 220,
              yFormat: (v) => f0(v),
              series: [
                ChartSeries(
                  '累積損益（元）',
                  [for (final e in r.equity) e.$2 * _riskMoney],
                  Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ],
              lines: const [ChartLine('0', 0, Colors.grey)],
              startLabel: r.equity.first.$1,
              endLabel: r.equity.last.$1,
            ),
          ],
        ),
      ),
      CardGrid(
        minItemWidth: 520,
        children: [
          SectionCard(
            title: '各策略',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('怎麼看：哪一種進場方式在這段期間比較有效；筆數太少（< 20）的不要太相信。', style: small),
                const SizedBox(height: 4),
                for (final e in r.byStrategy.entries)
                  _GroupRow(
                    tag: StrategyTag(code: e.key.code, label: e.key.label, dimmed: e.value.n == 0),
                    s: e.value,
                    money: _money,
                  ),
              ],
            ),
          ),
          if (r.byRegime.isNotEmpty)
            SectionCard(
              title: '不同市場狀態下的表現',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('怎麼看：訊號出現那天的市場狀態。推薦和持股頁的「歷史勝率」就是用這個分組算的。', style: small),
                  const SizedBox(height: 4),
                  for (final e in r.byRegime.entries)
                    _GroupRow(tag: Tag(e.key.label, regimeColor(e.key)), s: e.value, money: _money),
                ],
              ),
            ),
        ],
      ),
      SectionCard(
        title: '穩健度檢查：是實力還是運氣？（§15.2）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Compare('前段 70%（${r.fromDate} 起）', r.firstPart, '後段 30%（${r.splitDate} 起）', r.secondPart, _money),
            Text('參數沒有用這段資料最佳化過。前後兩段都賺，比較不像是巧合；只有一段賺，要小心。', style: small),
            const Divider(height: 20),
            _Compare('基本設定', o, '壓力測試', r.stressed, _money),
            Text('壓力測試：滑價 ×2、手續費 ×1.5、晚一天進場。條件變差之後還能接受，策略才算穩健。', style: small),
            const Divider(height: 20),
            KvRow(
              'Monte Carlo 最大回撤',
              '一般 ${_money(-r.mcDdMedian)}・運氣差 ${_money(-r.mcDd95)}',
              note:
                  '把交易順序隨機打亂 1,000 次，看「運氣不好時」帳面可能回落多少（95% 的情況不會比這更糟）。'
                  '用它決定每筆風險：如果運氣差時的回落你承受不了，就把每筆風險調小。',
            ),
          ],
        ),
      ),
      SectionCard(
        title: '出場原因',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('怎麼看：停損多不一定是壞事，重點是停損虧得少、移動停利賺得多。', style: small),
            for (final e in _reasons(r.trades).entries)
              KvRow(e.key, '${e.value.$1} 筆・平均 ${_money(e.value.$2 / e.value.$1)}'),
          ],
        ),
      ),
      SectionCard(
        title: '最近 40 筆交易',
        child: Column(
          children: [
            for (final t in r.trades.reversed.take(40))
              InkWell(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: t.code))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      StrategyTag(code: t.strategy.code, label: t.strategy.code),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${t.code} ${kBuiltinStocksByCode[t.code]?.name ?? ''}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${t.entryDate} 進 ${f2(t.entry)} → ${t.exitDate} 出 ${f2(t.exit)}・${t.exitReason}',
                              style: small,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _money(t.r),
                            style: TextStyle(fontWeight: FontWeight.w700, color: changeColor(context, t.r)),
                          ),
                          Text('${t.retPct >= 0 ? '+' : ''}${t.retPct.toStringAsFixed(1)}%', style: small),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const DisclaimerCard(
        text:
            '回測的限制：這是逐筆訊號統計（每筆固定承擔同樣的風險），不是投資組合模擬——沒有同時持股上限、資金排擠；'
            '還沒有基本面、籌碼分數；歷史資料只有本機抓的天數，樣本不大。過去的結果不代表未來。',
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

/// 回測怎麼做：六個步驟＋名詞解釋。
class _HowItWorks extends StatelessWidget {
  final bool expanded;
  const _HowItWorks({required this.expanded});

  static const _steps = [
    (Icons.search, '找訊號', '每天收盤後，用跟「推薦」完全相同的規則（A／B／C／D 訊號、一票否決、市場狀態、相對強度門檻）找出當天會被推薦的股票。'),
    (Icons.login, '隔天開盤進場', '第二天開盤買進。開盤超過「可接受最高買價」或開盤就漲停 → 放棄不追；開盤就跌到停損附近 → 訊號失效不買。'),
    (Icons.alt_route, '照計畫出場', '跌破停損就賣；漲到 +1R 停損拉到成本（保本）；到 2R 先賣一半；剩下用「最高價 − 3 ATR」移動停利；N 天沒有 +1R 就時間停損。'),
    (Icons.receipt_long, '扣掉成本', '買賣手續費各 0.1425%、證交稅 0.3%（ETF 0.1%）、滑價；跌停鎖死那天賣不掉。'),
    (Icons.visibility_off, '不偷看未來', '每天只用當天以前的資料判斷；名單包含之後下市的股票（沒有存活者偏差）；同一檔持有中不重複進場。'),
    (Icons.fact_check, '統計與檢驗', '算勝率、平均每筆、Profit Factor、最大回撤；再用前後段比較、壓力測試、Monte Carlo 檢查是不是運氣。'),
  ];

  static const _terms = [
    ('R（風險單位）', '進場價到停損的距離。+2R 代表賺到 2 倍當初願意虧的錢；−1R 就是照計畫停損。用 R 比較，不受股價高低和買多少影響。'),
    ('勝率', '賺錢的筆數比例。趨勢策略勝率 35%～50% 很正常，重點是賺的時候賺得比賠的時候多。'),
    ('平均每筆（期望值）', '每做一筆平均賺或賠多少。大於 0 才有長期優勢；這是最重要的數字。'),
    ('Profit Factor', '所有賺的錢 ÷ 所有賠的錢。< 1 是虧錢、1～1.3 優勢很薄、> 1.3 算不錯、> 2 很少見（要懷疑樣本太少）。'),
    ('最大回撤', '帳面從最高點最多回落多少。決定你要準備多少資金、心理撐不撐得住。'),
    ('壓力測試', '故意把條件變差（滑價加倍、成本提高、晚一天進場），看規則會不會一下子就不賺了。'),
    ('Monte Carlo', '把交易順序隨機打亂很多次，看運氣不好時連續虧損會讓帳面回落多深。'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          leading: Icon(Icons.menu_book_outlined, color: scheme.primary),
          title: const Text('回測怎麼做、數字怎麼看（重點說明）', style: TextStyle(fontWeight: FontWeight.w800)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            CardGrid(
              minItemWidth: 340,
              spacing: 10,
              children: [
                for (final (i, (icon, title, body)) in _steps.indexed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: scheme.primary,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 16, color: scheme.primary),
                                  const SizedBox(width: 4),
                                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(body, style: const TextStyle(fontSize: 12.5, height: 1.45)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('名詞解釋', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            for (final (k, v) in _terms)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(k, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(child: Text(v, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 白話結論：值得參考／普通／不建議照做，加上用元講的幾句話。
class _Verdict extends StatelessWidget {
  final BacktestResult r;
  final double riskMoney;
  const _Verdict({required this.r, required this.riskMoney});

  @override
  Widget build(BuildContext context) {
    final o = r.overall;
    String m(double x) => '${x >= 0 ? '+' : '−'}${f0((x * riskMoney).abs())} 元';
    final halvesOk = r.firstPart.n > 0 && r.secondPart.n > 0 && r.firstPart.avgR > 0 && r.secondPart.avgR > 0;
    final stressOk = r.stressed.avgR > 0;
    final (label, color, icon) = o.n < 30
        ? ('樣本太少，先別下結論', Colors.blueGrey, Icons.help_outline)
        : (o.profitFactor >= 1.3 && o.avgR >= 0.15 && halvesOk && stressOk
              ? ('值得參考', const Color(0xFF0B7A6F), Icons.verified)
              : (o.profitFactor >= 1 && o.avgR > 0
                    ? ('普通：有一點優勢，但不明顯', const Color(0xFFB7860B), Icons.balance)
                    : ('不建議照做：這段期間是虧的', AppColors.up, Icons.do_not_disturb_on)));
    final months = r.fromDate == null || r.toDate == null
        ? 0.0
        : DateTime.parse(r.toDate!).difference(DateTime.parse(r.fromDate!)).inDays / 30.4;
    BtStats? bestOf(Iterable<BtStats> xs) {
      final l = xs.where((s) => s.n >= 10).toList()..sort((a, b) => b.avgR.compareTo(a.avgR));
      return l.isEmpty ? null : l.first;
    }

    final bs = bestOf(r.byStrategy.values);
    final bestStrategy = bs == null ? null : r.byStrategy.entries.firstWhere((e) => identical(e.value, bs)).key;
    final br = bestOf(r.byRegime.values);
    final bestRegime = br == null ? null : r.byRegime.entries.firstWhere((e) => identical(e.value, br)).key;
    final lines = [
      '期間 ${r.fromDate} ～ ${r.toDate}，共 ${o.n} 筆交易${months >= 1 ? '（平均每月約 ${(o.n / months).toStringAsFixed(1)} 筆）' : ''}。',
      '每 10 筆大約 ${(o.winRate * 10).round()} 筆賺錢；賺的時候平均 ${m(o.avgWinR)}，賠的時候平均 ${m(o.avgLossR)}。',
      '假設每筆碰到停損虧 ${f0(riskMoney)} 元：全部加起來 ${m(o.totalR)}，平均每筆 ${m(o.avgR)}。',
      '最慘的一段帳面從高點回落 ${m(-o.maxDdR)}（最多連續虧 ${o.maxConsecLoss} 筆）；運氣更差時可能回落 ${m(-r.mcDd95)}。',
      halvesOk ? '前段和後段都賺錢，結果比較不像是巧合。' : '前段和後段的結果不一致，優勢可能不穩定，要保守看待。',
      stressOk ? '把滑價、成本加重、晚一天進場之後，平均每筆仍是 ${m(r.stressed.avgR)}，還算穩健。' : '壓力測試（成本加重、晚一天進場）後就轉成虧損，代表優勢很薄。',
      if (bestStrategy != null) '這段期間最有效的是「${bestStrategy.label}」（平均每筆 ${m(bs!.avgR)}）。',
      if (bestRegime != null) '在「${bestRegime.label}」市場下表現最好（平均每筆 ${m(br!.avgR)}）。',
    ];
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('白話結論', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        label,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Bullets(lines, BulletKind.info),
            const SizedBox(height: 4),
            Text(
              '判斷標準：至少 30 筆，Profit Factor ≥ 1.3、平均每筆 ≥ +0.15R、前後段都賺、壓力測試仍賺 → 值得參考。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label, value, hint;
  final Color? color;
  const _Kpi(this.label, this.value, this.hint, {this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 178,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
          Text(hint, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final Widget tag;
  final BtStats s;
  final String Function(double) money;
  const _GroupRow({required this.tag, required this.s, required this.money});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 118,
          child: Align(alignment: Alignment.centerLeft, child: tag),
        ),
        Expanded(
          child: s.n == 0
              ? const Text('沒有交易', style: TextStyle(fontSize: 12, color: Colors.grey))
              : Text(
                  '${s.n} 筆・勝率 ${(s.winRate * 100).toStringAsFixed(0)}%・PF ${s.profitFactor.isInfinite ? '∞' : s.profitFactor.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12.5),
                ),
        ),
        if (s.n > 0)
          Text(
            '平均 ${money(s.avgR)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: changeColor(context, s.avgR)),
          ),
      ],
    ),
  );
}

class _Compare extends StatelessWidget {
  final String la, lb;
  final BtStats a, b;
  final String Function(double) money;
  const _Compare(this.la, this.a, this.lb, this.b, this.money);

  @override
  Widget build(BuildContext context) {
    Widget col(String l, BtStats s) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('${s.n} 筆・勝率 ${(s.winRate * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
          Text(
            '平均每筆 ${money(s.avgR)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: changeColor(context, s.avgR)),
          ),
        ],
      ),
    );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [col(la, a), col(lb, b)]);
  }
}
