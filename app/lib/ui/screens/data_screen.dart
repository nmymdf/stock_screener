/// 「資料」頁：歷史資料的同步狀態、回看天數、存放位置、清除快取、版本號。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';
import '../widgets/common.dart';
import '../widgets/sync_status.dart';

class DataScreen extends StatelessWidget {
  const DataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionHeader(left: '歷史資料'),
        const SyncStatusCard(),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '回看天數（日曆天）\n建議 400 天：200 日均線、52 週新高、240 日線廣度都需要一年左右的資料；'
                    '天數越多第一次抓越久',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                DropdownButton<int>(
                  value: const [120, 180, 270, 400, 550].contains(store.lookbackDays) ? store.lookbackDays : null,
                  hint: Text('${store.lookbackDays} 天'),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final d in const [120, 180, 270, 400, 550]) DropdownMenuItem(value: d, child: Text('$d 天')),
                  ],
                  onChanged: store.syncing
                      ? null
                      : (v) {
                          if (v != null) store.setLookbackDays(v);
                        },
                ),
              ],
            ),
          ),
        ),
        const SectionHeader(left: '資料來源'),
        const RowList(
          children: [
            InfoRow(
              title: Text('推薦／市場／產業／回測／自訂篩選', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                '證交所「每日收盤行情」（上市，含加權指數）＋櫃買中心「上櫃股票行情」，每個交易日一次抓全市場，'
                '抓過的日子存在本機，不會重抓。推薦、市場、產業、回測都用這份資料。',
              ),
            ),
            InfoRow(
              title: Text('今日雷達', style: TextStyle(fontSize: 13)),
              subtitle: Text('證交所「基本市況報導」即時報價（跟 stock_acc 同一個來源），每次掃描即時抓。'),
            ),
          ],
        ),
        const SectionHeader(left: '本機存檔'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(store.dataDir ?? '（讀取中）', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: store.syncing ? null : () => _confirmClear(context, store),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除所有歷史資料'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, HistoryStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除歷史資料？'),
        content: const Text('會刪掉本機所有已抓的每日收盤行情，之後要重新抓。篩選條件會保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (ok == true) await store.clearAll();
  }
}
