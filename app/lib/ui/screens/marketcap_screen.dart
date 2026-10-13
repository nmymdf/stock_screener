/// 「市值」：台股上市公司市值（發行股數 × 股價）排行，附收盤、一年走勢、量和地雷標記。
/// 只是排行參考，不是推薦名單。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bluechip.dart';
import '../../core/lt_analysis.dart';
import '../../data/longterm_store.dart';
import '../layout.dart';
import '../widgets/common.dart';
import '../widgets/lt_widgets.dart';
import '../widgets/score_widgets.dart';
import 'stock_report_screen.dart';

class MarketCapScreen extends StatefulWidget {
  const MarketCapScreen({super.key});

  @override
  State<MarketCapScreen> createState() => _MarketCapScreenState();
}

class _MarketCapScreenState extends State<MarketCapScreen> {
  int _show = 30;

  @override
  Widget build(BuildContext context) {
    final lt = context.watch<LongTermStore>();
    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeader(
          icon: Icons.leaderboard_outlined,
          title: '市值排行',
          subtitle: '上市公司市值（發行股數 × 股價）由大到小；只是排行參考，不是推薦名單',
          trailing: lt.result == null
              ? null
              : Text('資料到 ${lt.result!.date}', style: Theme.of(context).textTheme.bodySmall),
        ),
        PackGate(
          builder: (context, r) => _List(r: r, show: _show, onMore: () => setState(() => _show += 30)),
        ),
        const SizedBox(height: 8),
        const DisclaimerCard(text: '依公開資料算出來的參考，不是投資建議。'),
      ],
    );
  }
}

class _List extends StatelessWidget {
  final LtResult r;
  final int show;
  final VoidCallback onMore;
  const _List({required this.r, required this.show, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final s = r.data.samples.length - 1;
    final rank = capRanking(r.data, s);
    if (rank.isEmpty) {
      return const SectionCard(title: '需要更新資料包', child: Text('新版資料包加入了每家公司的發行股數（算市值用），請到「工具」更新資料包。'));
    }
    final total = rank.fold(0.0, (a, x) => a + x.$2);
    final small = Theme.of(context).textTheme.bodySmall;
    return SectionCard(
      title: '市值前 ${show.clamp(0, rank.length)} 大',
      trailing: Text('上市 ${rank.length} 家，合計 ${(total / 1e12).toStringAsFixed(1)} 兆元', style: small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rank.length && i < show; i++)
            _Row(r: r, rank: i + 1, si: rank[i].$1, cap: rank[i].$2, total: total),
          if (show < rank.length)
            Center(
              child: TextButton(onPressed: onMore, child: const Text('再多看 30 檔')),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final LtResult r;
  final int rank, si;
  final double cap, total;
  const _Row({required this.r, required this.rank, required this.si, required this.cap, required this.total});

  @override
  Widget build(BuildContext context) {
    final st = r.data.stocks[si];
    final x = r.live.of(si);
    final mines = x == null ? const <String>[] : landmineReasonsOf(x);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockReportScreen(code: st.code))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text('$rank', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${st.code} ${st.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      CloseText(st.code),
                      if (mines.isNotEmpty) const Tag('地雷', Color(0xFFB71C1C), filled: true),
                    ],
                  ),
                  Text(
                    '市值 ${cap >= 1e12 ? '${(cap / 1e12).toStringAsFixed(2)} 兆' : '${(cap / 1e8).toStringAsFixed(0)} 億'}元・佔上市市值 ${pc(cap / total, 1)}'
                    '${mines.isEmpty ? '' : '・${mines.join('、')}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  PriceTrend(st.code, width: 220, height: 44),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
