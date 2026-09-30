/// 歷史資料的狀態卡：目前有幾天資料、缺幾天、同步進度、錯誤訊息。
/// 技術選股頁和資料頁共用。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/history_store.dart';

class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final days = store.tradingDates.length;
    final missing = store.missingDates().length;
    final scheme = Theme.of(context).colorScheme;

    final String summary;
    if (days == 0) {
      summary =
          '還沒有歷史資料。第一次要從證交所、櫃買中心抓最近 ${store.lookbackDays} 天的每日收盤行情，'
          '為了不被證交所封鎖，每天間隔幾秒，大約要 ${_eta(missing, store)}。抓到的會存在本機，之後只補新的日子。';
    } else {
      summary =
          '已有 $days 個交易日的資料（最新 ${store.latestDate}）'
          '${missing > 0 ? '，還有 $missing 天沒抓（約 ${_eta(missing, store)}）' : '，已是最新'}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary, style: const TextStyle(fontSize: 12)),
            if (store.syncing) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: store.syncTotal == 0 ? null : store.syncDone / store.syncTotal),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '同步中… ${store.syncDone} / ${store.syncTotal} 天（可以先用已抓到的資料篩選）',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  TextButton(onPressed: store.cancelSync, child: const Text('停止')),
                ],
              ),
            ] else if (missing > 0) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: store.sync,
                icon: const Icon(Icons.download, size: 18),
                label: Text(days == 0 ? '開始抓歷史資料' : '補抓 $missing 天資料'),
              ),
            ],
            if (store.lastError != null && !store.syncing) ...[
              const SizedBox(height: 6),
              Text(store.lastError!, style: TextStyle(fontSize: 11, color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  String _eta(int days, HistoryStore store) {
    final secs = days * (store.requestGap.inMilliseconds / 1000 + 1);
    if (secs < 60) return '${secs.round()} 秒';
    return '${(secs / 60).ceil()} 分鐘';
  }
}
