/// 持股的輸入畫面：新增持股（可從推薦帶入計畫）、加碼、賣出、修改設定。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../data/holdings_store.dart';
import '../../data/stock_catalog.dart';
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
  const PlanPrefill({this.strategy, this.entry, this.stop, this.target, this.reason});
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
    _existing = _code == null ? null : context.read<HoldingsStore>().openFor(_code!);
    _date = ymd(taipeiNow());
    _style = defaultStyleFor(widget.plan?.strategy);
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
                      _existing = context.read<HoldingsStore>().openFor(c);
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

  Future<void> _save() async {
    final stop = parseInput(_stop.text);
    if (_style == HoldStyle.custom && stop == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('「自己設定」一定要填停損價')));
      return;
    }
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
              FilledButton(onPressed: _save, child: const Text('儲存')),
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
