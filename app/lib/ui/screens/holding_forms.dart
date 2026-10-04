/// 持股的輸入畫面：新增持股（可從推薦帶入計畫）、加碼、賣出、修改設定。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/stock_catalog.dart';
import '../../logic/engine/horizon.dart';
import '../../logic/engine/signals.dart';
import '../../logic/holding_eval.dart';
import '../../models/holding.dart';
import '../format.dart';
import '../holding_helpers.dart';
import '../widgets/score_widgets.dart';

/// 從推薦／個股報告帶進來的計畫。
class PlanPrefill {
  final Strategy? strategy;
  final double? entry;
  final double? stop;
  final double? target;
  final String? reason;

  /// 買進當下的判斷（會存進持股，之後每天對照「理由還成立嗎」）。
  final String? opportunity;
  final int? duration;
  final String? confidence;
  final List<String> thesis;

  const PlanPrefill({
    this.strategy,
    this.entry,
    this.stop,
    this.target,
    this.reason,
    this.opportunity,
    this.duration,
    this.confidence,
    this.thesis = const [],
  });
}

class AddHoldingPage extends StatefulWidget {
  final String? code;
  final PlanPrefill? plan;
  const AddHoldingPage({super.key, this.code, this.plan});

  @override
  State<AddHoldingPage> createState() => _AddHoldingPageState();
}

class _AddHoldingPageState extends State<AddHoldingPage> {
  String? _code;
  late String _date;
  final _price = TextEditingController();
  final _shares = TextEditingController(text: '1000');
  final _stop = TextEditingController();
  final _target = TextEditingController();
  final _note = TextEditingController();
  late HoldStyle _style;
  bool _usePlan = true;
  bool _confirmAvgDown = false;

  /// 打開這頁時就決定是「新增」還是「加碼」，存檔後不會中途變換模式。
  Holding? _existing;

  @override
  void initState() {
    super.initState();
    final store = context.read<HistoryStore>();
    _code = widget.code;
    _existing = _code == null ? null : context.read<HoldingsStore>().openFor(_code!, source: HoldingSource.manual);
    _date = ymd(taipeiNow());
    _style = defaultStyleFor(widget.plan?.strategy, duration: widget.plan?.duration);
    final p = widget.plan;
    final last = _code == null
        ? null
        : (store.rawSeriesOf(_code!).isEmpty ? null : store.rawSeriesOf(_code!).last.close);
    final entry = p?.entry ?? last;
    if (entry != null) _price.text = entry.toStringAsFixed(2);
  }

  @override
  void dispose() {
    for (final c in [_price, _shares, _stop, _target, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = taipeiNow();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (d != null) setState(() => _date = ymd(d));
  }

  Future<void> _save() async {
    final holdings = context.read<HoldingsStore>();
    final code = _code;
    final price = parseInput(_price.text);
    final shares = parseInput(_shares.text)?.round();
    if (code == null || price == null || price <= 0 || shares == null || shares <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請選股票，並填正確的價格和股數')));
      return;
    }
    final existing = _existing;
    if (existing != null) {
      final warn = averageDownWarning(existing, price, lastClose: _lastClose(code));
      if (warn != null && !_confirmAvgDown) {
        setState(() {});
        return;
      }
      // 記憶體裡的資料會立刻更新，寫入檔案在背景完成，不用等
      unawaited(holdings.addBuy(existing.id, BuyLot(_date, price, shares)));
    } else {
      final p = _usePlan ? widget.plan : null;
      final stop = parseInput(_stop.text);
      final target = parseInput(_target.text);
      if (_style == HoldStyle.custom && stop == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('「自己設定」一定要填停損價')));
        return;
      }
      unawaited(
        holdings.upsert(
          Holding(
            id: holdings.newId(code),
            code: code,
            style: _style,
            buys: [BuyLot(_date, price, shares)],
            manualStop: stop,
            manualTarget: _style == HoldStyle.custom ? target : null,
            strategy: p?.strategy?.code,
            planStop: p?.stop,
            planTarget: p?.target,
            reason: p?.reason,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            opportunity: widget.plan?.opportunity,
            duration: widget.plan?.duration,
            confidence: widget.plan?.confidence,
            thesis: widget.plan?.thesis ?? const [],
          ),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  double? _lastClose(String code) {
    final raw = context.read<HistoryStore>().rawSeriesOf(code);
    return raw.isEmpty ? null : raw.last.close;
  }

  @override
  Widget build(BuildContext context) {
    final existing = _existing;
    final price = parseInput(_price.text);
    final warn = existing != null && price != null
        ? averageDownWarning(existing, price, lastClose: _lastClose(_code!))
        : null;
    final p = widget.plan;
    return Scaffold(
      appBar: AppBar(title: Text(existing != null ? '加碼（記錄買進）' : '新增持股')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_code == null)
                _StockPicker(
                  onPicked: (c) {
                    setState(() {
                      _code = c;
                      _existing = context.read<HoldingsStore>().openFor(c, source: HoldingSource.manual);
                    });
                    final last = _lastClose(c);
                    if (last != null) _price.text = last.toStringAsFixed(2);
                  },
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '$_code ${kBuiltinStocksByCode[_code]?.name ?? ''}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  subtitle: existing != null
                      ? Text('已經持有 ${existing.shares} 股（平均成本 ${f2(existing.avgCost)}），這次會記錄成加碼')
                      : null,
                  trailing: widget.code == null
                      ? TextButton(
                          onPressed: () => setState(() {
                            _code = null;
                            _existing = null;
                          }),
                          child: const Text('換一檔'),
                        )
                      : null,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '買進價格'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _shares,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '股數（1 張 = 1000 股）'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event, size: 18),
                label: Text('買進日期：$_date'),
              ),
              if (warn != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('⚠ 禁止向下攤平', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(warn, style: const TextStyle(fontSize: 13)),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _confirmAvgDown,
                          onChanged: (v) => setState(() => _confirmAvgDown = v ?? false),
                          title: const Text('我了解風險，這筆是已經成交的紀錄，仍要記下來', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (existing == null && p?.duration != null) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: '買進當下的判斷（會一起記下來）',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p!.opportunity ?? ''}・預估 D${p.duration}（${kDurationRange[p.duration]}）・信心 ${p.confidence ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (p.thesis.isNotEmpty) Bullets(p.thesis.take(4).toList(), BulletKind.good),
                      Text('之後每天會對照這些理由還成立嗎（健康度），持有期間會隨證據升級或降級。', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
              if (existing == null) ...[
                const SizedBox(height: 16),
                const Text('持有方式（決定停損和出場規則）', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in HoldStyle.values)
                      ChoiceChip(
                        label: Text('${s.label}（${s.period}）'),
                        selected: _style == s,
                        onSelected: (_) => setState(() => _style = s),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_style.rules, style: Theme.of(context).textTheme.bodySmall),
                if (p != null && p.stop != null && (_style == HoldStyle.short || _style == HoldStyle.swing))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _usePlan,
                    onChanged: (v) => setState(() => _usePlan = v),
                    title: Text(
                      '使用推薦時的停損 ${f2(p.stop!)}${p.target != null ? '、目標 ${f2(p.target!)}' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: p.reason == null ? null : Text('推薦理由：${p.reason}', style: const TextStyle(fontSize: 11)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _stop,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: _style == HoldStyle.custom ? '停損價（必填）' : '停損價（選填，只能比規則算的高）',
                        ),
                      ),
                    ),
                    if (_style == HoldStyle.custom) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _target,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: '目標價（選填）'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: '備註（選填）'),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: warn != null && !_confirmAvgDown ? null : _save,
                child: Text(existing != null ? '記錄加碼' : '加入我的持股'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockPicker extends StatelessWidget {
  final ValueChanged<String> onPicked;
  const _StockPicker({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Autocomplete<StockInfo>(
      displayStringForOption: (s) => '${s.code} ${s.name}',
      optionsBuilder: (v) => searchStocks(v.text).take(30),
      onSelected: (s) => onPicked(s.code),
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        autofocus: true,
        decoration: const InputDecoration(labelText: '股票代號或名稱', prefixIcon: Icon(Icons.search)),
      ),
    );
  }
}

/// 記錄賣出。
class SellPage extends StatefulWidget {
  final Holding holding;
  final HoldingEval eval;
  const SellPage({super.key, required this.holding, required this.eval});

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  late String _date;
  final _price = TextEditingController();
  final _shares = TextEditingController();
  late String _reason;

  static const _reasons = ['停損', '保本停損', '移動停利', '到目標先賣一半', '時間停損', '趨勢轉弱', '其他'];

  @override
  void initState() {
    super.initState();
    _date = ymd(taipeiNow());
    final e = widget.eval;
    if (e.lastClose != null) _price.text = e.lastClose!.toStringAsFixed(2);
    final half = e.state == HoldState.exit && e.headline.contains('先賣一半');
    _shares.text = (half ? (widget.holding.shares / 2).round() : widget.holding.shares).toString();
    _reason = switch (e.state) {
      HoldState.stopLoss => '停損',
      HoldState.exit when half => '到目標先賣一半',
      HoldState.exit when e.headline.contains('時間停損') => '時間停損',
      HoldState.exit when e.headline.contains('季線') => '趨勢轉弱',
      HoldState.exit when e.headline.contains('保本') => '保本停損',
      HoldState.exit => '移動停利',
      _ => '其他',
    };
  }

  @override
  void dispose() {
    _price.dispose();
    _shares.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = parseInput(_price.text);
    final shares = parseInput(_shares.text)?.round();
    if (price == null || price <= 0 || shares == null || shares <= 0 || shares > widget.holding.shares) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('請填正確的價格，股數不能超過持有的 ${widget.holding.shares} 股')));
      return;
    }
    unawaited(context.read<HoldingsStore>().addSell(widget.holding.id, SellLot(_date, price, shares, reason: _reason)));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.holding;
    return Scaffold(
      appBar: AppBar(title: Text('賣出 ${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('目前持有 ${h.shares} 股，平均成本 ${f2(h.avgCost)}'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '賣出價格'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _shares,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '股數'),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(label: const Text('全部'), onPressed: () => setState(() => _shares.text = '${h.shares}')),
                  ActionChip(
                    label: const Text('一半'),
                    onPressed: () => setState(() => _shares.text = '${(h.shares / 2).round()}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final now = taipeiNow();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.parse(_date),
                    firstDate: DateTime.parse(h.firstBuyDate),
                    lastDate: DateTime(now.year, now.month, now.day),
                  );
                  if (d != null) setState(() => _date = ymd(d));
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text('賣出日期：$_date'),
              ),
              const SizedBox(height: 12),
              const Text('賣出原因', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in _reasons)
                    ChoiceChip(label: Text(r), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('記錄賣出')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 修改持有方式、停損、目標、備註。
class EditHoldingPage extends StatefulWidget {
  final Holding holding;
  const EditHoldingPage({super.key, required this.holding});

  @override
  State<EditHoldingPage> createState() => _EditHoldingPageState();
}

class _EditHoldingPageState extends State<EditHoldingPage> {
  late HoldStyle _style = widget.holding.style;
  late final _stop = TextEditingController(text: widget.holding.manualStop?.toStringAsFixed(2) ?? '');
  late final _target = TextEditingController(text: widget.holding.manualTarget?.toStringAsFixed(2) ?? '');
  late final _note = TextEditingController(text: widget.holding.note ?? '');

  @override
  void dispose() {
    _stop.dispose();
    _target.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save((bool, String)? check) async {
    final stop = parseInput(_stop.text);
    if (_style == HoldStyle.custom && stop == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('「自己設定」一定要填停損價')));
      return;
    }
    if (check != null && check.$1) return;
    unawaited(
      context.read<HoldingsStore>().upsert(
        widget.holding.copyWith(
          style: _style,
          manualStop: stop,
          manualTarget: _style == HoldStyle.custom ? parseInput(_target.text) : null,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final e = evalFor(context, widget.holding);
    final check = styleUpgradeCheck(widget.holding, _style, e);
    final customWhileLosing =
        _style == HoldStyle.custom && widget.holding.style != HoldStyle.custom && (e.rNow ?? 0) < 0;
    return Scaffold(
      appBar: AppBar(title: const Text('修改持股設定')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('持有方式', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in HoldStyle.values)
                    ChoiceChip(
                      label: Text('${s.label}（${s.period}）'),
                      selected: _style == s,
                      onSelected: (_) => setState(() => _style = s),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_style.rules, style: Theme.of(context).textTheme.bodySmall),
              if (check != null || customWhileLosing) ...[
                const SizedBox(height: 8),
                Card(
                  color: check?.$1 ?? false
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      check?.$2 ?? '這筆目前虧損：改成「自己設定」再把停損往下調，等於把虧損放大。只有在你很確定、並在備註寫下理由時才這樣做。',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _stop,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _style == HoldStyle.custom ? '停損價（必填）' : '停損價（選填，只能比規則算的高）',
                  helperText: '想重新設定一個比較低的停損，請改用「自己設定」',
                ),
              ),
              if (_style == HoldStyle.custom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '目標價（選填）'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: '備註'),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: check?.$1 ?? false ? null : () => _save(check), child: const Text('儲存')),
              const SizedBox(height: 8),
              const SectionCard(
                child: Text(
                  '停損只會往上調、不會往下：這是規格書「判斷錯誤時小損離場」的原則。'
                  '如果真的要改成比較低的停損，請改成「自己設定」並寫下理由在備註裡。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 刪除整筆持股（只限手動／模擬）：先確認，刪掉回傳 true。
Future<bool> confirmDeleteHolding(BuildContext context, Holding h) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('刪除 ${h.code} ${kBuiltinStocksByCode[h.code]?.name ?? ''}？'),
      content: const Text('會刪掉這檔的所有買賣紀錄和每日追蹤，刪除後無法復原。\n如果只是賣掉了，請用「記錄賣出」，交易紀錄才會留下來。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('刪除'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await context.read<HoldingsStore>().remove(h.id);
    return true;
  }
  return false;
}

/// 持股卡片右上角的「⋮」選單。
class HoldingMenu extends StatelessWidget {
  final Holding h;
  final HoldingEval e;
  const HoldingMenu({super.key, required this.h, required this.e});

  @override
  Widget build(BuildContext context) {
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return PopupMenuButton<String>(
      tooltip: '更多動作',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            push(EditHoldingPage(holding: h));
          case 'sell':
            push(SellPage(holding: h, eval: e));
          case 'buy':
            push(AddHoldingPage(code: h.code));
          case 'delete':
            confirmDeleteHolding(context, h);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(leading: Icon(Icons.tune), title: Text('修改設定（持有方式、停損、備註）')),
        ),
        if (!h.fromStockAcc && !h.closed) ...[
          const PopupMenuItem(
            value: 'sell',
            child: ListTile(leading: Icon(Icons.sell_outlined), title: Text('記錄賣出')),
          ),
          const PopupMenuItem(
            value: 'buy',
            child: ListTile(leading: Icon(Icons.add), title: Text('加碼（記錄買進）')),
          ),
        ],
        if (!h.fromStockAcc)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('刪除這筆持股')),
          ),
      ],
    );
  }
}

/// 修改或刪除一筆買進／賣出紀錄（只限手動／模擬）。
Future<void> editLotDialog(BuildContext context, Holding h, {required bool buy, required int index}) async {
  final b = buy ? h.buys[index] : null;
  final s = buy ? null : h.sells[index];
  var date = b?.date ?? s!.date;
  final price = TextEditingController(text: (b?.price ?? s!.price).toStringAsFixed(2));
  final shares = TextEditingController(text: '${b?.shares ?? s!.shares}');
  final reason = TextEditingController(text: s?.reason ?? '');
  String? err;
  final holdings = context.read<HoldingsStore>();

  Future<void> save(BuildContext ctx, {bool delete = false}) async {
    final buys = [...h.buys];
    final sells = [...h.sells];
    if (delete) {
      buy ? buys.removeAt(index) : sells.removeAt(index);
    } else {
      final p = parseInput(price.text), n = parseInput(shares.text)?.round();
      if (p == null || n == null) {
        err = '請填正確的價格和股數';
        return;
      }
      if (buy) {
        buys[index] = BuyLot(date, p, n, fee: b!.fee);
      } else {
        sells[index] = SellLot(
          date,
          p,
          n,
          reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
          fee: s!.fee,
          tax: s.tax,
        );
      }
    }
    final problem = validateLots(buys, sells);
    if (problem != null) {
      err = problem;
      return;
    }
    await holdings.upsert(h.copyWith(buys: buys, sells: sells));
    if (ctx.mounted) Navigator.pop(ctx);
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(buy ? '修改買進紀錄' : '修改賣出紀錄'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final now = taipeiNow();
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.parse(date),
                    firstDate: DateTime(now.year - 10),
                    lastDate: DateTime(now.year, now.month, now.day),
                  );
                  if (d != null) setState(() => date = ymd(d));
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text('日期：$date'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '價格'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: shares,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '股數（1 張 = 1000 股）'),
              ),
              if (!buy) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: '賣出原因（選填）'),
                ),
              ],
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 13)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await save(ctx, delete: true);
              if (ctx.mounted) setState(() {});
            },
            icon: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            label: Text('刪除這筆', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await save(ctx);
              if (ctx.mounted) setState(() {});
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    ),
  );
}
