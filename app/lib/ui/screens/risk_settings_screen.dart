/// 資金與風險設定（規格書 §11、§19）：交易計畫的建議張數依這裡計算。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../../logic/risk.dart';
import '../format.dart';
import '../widgets/score_widgets.dart';

class RiskSettingsScreen extends StatelessWidget {
  const RiskSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final r = store.risk;
    void set(RiskSettings n) => store.setRisk(n);
    return Scaffold(
      appBar: AppBar(title: const Text('資金與風險設定')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              SectionCard(
                title: '總資金',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: r.capital.round().toString(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(suffixText: '元'),
                      onChanged: (v) {
                        final x = double.tryParse(v.replaceAll(',', ''));
                        if (x != null && x > 0) set(r.copyWith(capital: x));
                      },
                    ),
                    const SizedBox(height: 4),
                    Text('目前 ${f0(r.capital)} 元', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              _Choice(
                title: '單筆最大風險',
                note: '碰到停損時，這筆最多虧掉總資金的幾 %。規格書建議 0.25%～0.5%。',
                value: r.riskPct,
                options: const [0.25, 0.5, 0.75, 1.0],
                fmt: (v) => '$v%',
                onChanged: (v) => set(r.copyWith(riskPct: v)),
              ),
              _Choice(
                title: '單檔最大曝險',
                note: '一檔股票最多佔總資金幾 %，避免停損很近時買太多。建議 8%～10%。',
                value: r.maxPositionPct,
                options: const [5.0, 8.0, 10.0, 15.0, 20.0],
                fmt: (v) => '${v.toStringAsFixed(0)}%',
                onChanged: (v) => set(r.copyWith(maxPositionPct: v)),
              ),
              _Choice(
                title: '目前帳戶回撤',
                note: '從資金最高點回落了多少。回撤越大，系統自動降低每筆風險（§11.4）：5–10% × 0.8、10–15% × 0.5、超過 15% 停止新單。',
                value: r.drawdownPct,
                options: const [0.0, 5.0, 10.0, 15.0],
                fmt: (v) =>
                    v == 0 ? '0–5%' : (v == 15 ? '15% 以上' : '${v.toStringAsFixed(0)}–${(v + 5).toStringAsFixed(0)}%'),
                onChanged: (v) => set(r.copyWith(drawdownPct: v)),
              ),
              _Choice(
                title: '估計滑價（單邊）',
                note: '算張數時把來回滑價算進每股風險，回測也用這個值。',
                value: r.slippagePct,
                options: const [0.0, 0.05, 0.1, 0.2, 0.3],
                fmt: (v) => '$v%',
                onChanged: (v) => set(r.copyWith(slippagePct: v)),
              ),
              SectionCard(
                title: '換算',
                child: Text(
                  '每筆最多承擔 ${f0(r.capital * r.riskPct / 100 * r.drawdownMultiplier)} 元風險；'
                  '單檔最多 ${f0(r.capital * r.maxPositionPct / 100)} 元。${r.drawdownNote}。\n'
                  '規格書也建議：最大持股 8–12 檔、單一產業不超過 20–25%、所有部位同時碰停損的總損失（Portfolio Heat）'
                  '不超過 3–5%——這幾項要看你實際的持股，目前 App 沒有接券商部位，請自行控管。',
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String title, note;
  final double value;
  final List<double> options;
  final String Function(double) fmt;
  final ValueChanged<double> onChanged;
  const _Choice({
    required this.title,
    required this.note,
    required this.value,
    required this.options,
    required this.fmt,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SectionCard(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final o in options)
              ChoiceChip(label: Text(fmt(o)), selected: value == o, onSelected: (_) => onChanged(o)),
          ],
        ),
        const SizedBox(height: 4),
        Text(note, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
