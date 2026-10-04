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
  const AnalysisGate({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final a = store.analysis;
    final children = <Widget>[];
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
        Text('台股選股系統', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text(
          '依照「市場 → 產業 → 個股 → 交易計畫」的順序，每天收盤後分析全部上市櫃股票：\n'
          '1. 市場環境：用全市場廣度算 Market Score，決定現在適不適合做多、最多放多少部位。\n'
          '2. 產業輪動：找資金正在流入的產業。\n'
          '3. 個股評分：趨勢、相對強度、動能、量價、突破、波動壓縮，逐項給分。\n'
          '4. 進場訊號：突破、回檔、趨勢延續、均值回歸四種模式。\n'
          '5. 一票否決與交易計畫：流動性、停損過寬、報酬風險比不足就不推薦；推薦的每一檔都有停損、目標和建議張數。',
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
