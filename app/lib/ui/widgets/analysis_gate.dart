/// 推薦／市場／產業頁共用的外框：還沒資料就引導去抓、分析中顯示進度，
/// 有結果才交給各頁面畫內容。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../layout.dart';
import '../../data/history_store.dart';
import '../../logic/engine/analysis.dart';
import 'common.dart';
import 'sync_status.dart';

class AnalysisGate extends StatelessWidget {
  final List<Widget> Function(BuildContext context, AnalysisResult a) builder;

  /// 不管有沒有每日行情都要顯示的內容（例如市場頁的長期環境）。
  final List<Widget> header;
  const AnalysisGate({super.key, required this.builder, this.header = const []});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final a = store.analysis;
    final children = <Widget>[...header];
    if (store.tradingDates.isEmpty) {
      children.addAll([const _Intro(), const SizedBox(height: 8), const SyncStatusCard()]);
    } else if (a == null || (a.latestDate == null && store.analyzing)) {
      children.addAll([
        const SyncStatusCard(),
        const Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在分析全市場…（市場廣度、產業、每一檔的分數與訊號）')],
          ),
        ),
      ]);
    } else {
      if (store.syncing || store.missingDates().isNotEmpty) children.add(const SyncStatusCard());
      if (store.analyzing) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('資料有更新，正在重新分析…', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      }
      if (store.analysisError != null) {
        children.add(Text(store.analysisError!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
      }
      children.addAll(builder(context, a));
    }
    return ListView(padding: pagePadding(context), children: children);
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('每日行情', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text(
          '這一頁用的是每天的上市櫃收盤行情（短線訊號、每日市場分數、產業輪動、持股追蹤都靠它）。\n'
          '在「組合」頁下載長期資料包後，最近一年多的每日行情會自動匯入，不用再一天一天抓；'
          '也可以按下面的按鈕直接跟證交所、櫃買中心抓（比較慢）。',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        SizedBox(height: 8),
        DisclaimerCard(
          text:
              '這是機械化的篩選與排序，不是投資建議、也不是預測。系統的目標是找出「目前條件較有利」的股票，'
              '並把每次判斷錯誤的損失限制在可控範圍內——沒有任何系統能保證賺錢。',
        ),
      ],
    );
  }
}
