/// 「選股名單成績單」：過去每個月的名單，抱 3、6 個月以後跟大盤比的真實成績。
library;

import 'package:flutter/material.dart';

import '../../core/scorecard.dart';
import '../layout.dart';
import '../theme.dart';
import 'lt_widgets.dart';
import 'score_widgets.dart';

/// 一句話的白話結論（組合頁、回測頁共用）。
String scorecardSummary(Scorecard sc) {
  final h = sc.of(126) ?? sc.horizons.lastOrNull;
  if (h == null || h.n == 0) return '資料還不夠，算不出選股名單過去的成績。';
  return '過去 ${h.n} 次選股名單抱${h.label}：贏大盤 ${pc(h.winRate)}、平均${h.avgExcess >= 0 ? '多' : '少'}賺 '
      '${pc(h.avgExcess.abs(), 1)}；大盤下跌時贏 ${pc(h.downWin)}（少跌）。';
}

/// 依成績下的結論：不說好聽話。
String scorecardVerdict(Scorecard sc) {
  final h = sc.of(126) ?? sc.horizons.lastOrNull;
  if (h == null || h.n == 0) return '';
  if (h.winRate >= 0.6 && h.avgExcess > 0.01) {
    return '過去多數時候贏大盤，但市場會變，不保證未來也一樣；還是建議搭配大盤核心。';
  }
  if (h.winRate < 0.5 || h.avgExcess < 0) {
    return '選股名單平均沒有贏大盤：大盤大漲（尤其台積電帶頭）時常常落後；長處是大盤下跌時比較抗跌、'
        '也避開虧損和營收衰退的股票。所以建議一部分放大盤核心（0050），選股只當衛星。';
  }
  return '選股名單跟大盤差不多，勝負大約一半；長處是下跌時比較抗跌，建議搭配大盤核心。';
}

class ScorecardCard extends StatelessWidget {
  final Scorecard sc;
  const ScorecardCard({super.key, required this.sc});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    if (sc.horizons.every((h) => h.n == 0)) {
      return const SectionCard(title: '選股名單成績單', child: Text('資料還不夠，算不出過去的成績。'));
    }
    final short = sc.horizons.first;
    final years = <String, Map<int, YearScore>>{};
    for (final h in sc.horizons) {
      for (final y in h.years) {
        (years[y.year] ??= {})[h.days] = y;
      }
    }
    final recent = short.rows.skip(short.n > 12 ? short.n - 12 : 0).toList().reversed.toList();
    return SectionCard(
      title: '選股名單成績單',
      trailing: Text('每次 ${sc.size} 檔、只看選股部分', style: small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '倒回過去每一個月，只用當時看得到的資料選出名單，看抱 3 個月、6 個月以後有沒有贏大盤（加權報酬指數，含息）。'
            '這是選股名單的真實成績，贏的、輸的都列出來。',
            style: TextStyle(fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 8),
          CardGrid(minItemWidth: 260, spacing: 10, children: [for (final h in sc.horizons) _HorizonTile(h: h)]),
          const SizedBox(height: 6),
          Text(scorecardVerdict(sc), style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600)),
          const Divider(height: 20),
          Text('各年度：贏大盤的次數比例', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 52),
              for (final h in sc.horizons) Expanded(child: Text('抱${h.label}', style: small)),
              Expanded(child: Text('${sc.horizons.last.label}平均：名單／大盤', style: small)),
            ],
          ),
          for (final e in years.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  for (final h in sc.horizons)
                    Expanded(
                      child: e.value[h.days] == null
                          ? Text('—', style: small)
                          : Text(
                              '${pc(e.value[h.days]!.winRate)}（${e.value[h.days]!.n}）',
                              style: TextStyle(
                                fontSize: 13,
                                color: e.value[h.days]!.winRate >= 0.5 ? AppColors.up : AppColors.down,
                              ),
                            ),
                    ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final y = e.value[sc.horizons.last.days];
                        return Text(y == null ? '—' : '${sp(y.ret)}／${sp(y.bench)}', style: small);
                      },
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 20),
          Text('最近幾次名單（抱${short.label}）', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final r in sc.inProgress.reversed) _CohortTile(r: r, running: true),
          for (final r in recent) _CohortTile(r: r),
          const SizedBox(height: 6),
          Text(
            '算法：每個檢視日假設手上沒有股票、照規則重新選一次名單；隔天收盤每檔買一樣多錢，含配息、不扣成本。'
            '每月一次、一抱好幾個月，前後期間會重疊，所以次數不是互相獨立的樣本。',
            style: small,
          ),
        ],
      ),
    );
  }
}

class _HorizonTile extends StatelessWidget {
  final HorizonScore h;
  const _HorizonTile({required this.h});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = h.winRate >= 0.5;
    Widget line(String a, String b) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Expanded(child: Text(a, style: const TextStyle(fontSize: 12.5))),
          Text(b, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('抱${h.label}（${h.n} 次）', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '贏大盤 ${pc(h.winRate)}',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: good ? AppColors.up : AppColors.down),
          ),
          line('平均比大盤', '${sp(h.avgExcess)}（中位數 ${sp(h.medianExcess)}）'),
          line('名單平均／大盤平均', '${sp(h.avgRet)}／${sp(h.avgBench)}'),
          line('大盤上漲時贏（${h.upRows.length} 次）', pc(h.upWin)),
          line('大盤下跌時贏（${h.downRows.length} 次）', pc(h.downWin)),
          line('贏「平均一檔股票」', '${pc(h.vsAvgWin)}（${sp(h.vsAvgExcess)}）'),
          line('單一檔贏大盤', pc(h.stockWinRate)),
          line('最近 12 次贏大盤', pc(h.recentWinRate(12))),
        ],
      ),
    );
  }
}

class _CohortTile extends StatelessWidget {
  final CohortRow r;
  final bool running;
  const _CohortTile({required this.r, this.running = false});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(r.date, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              Expanded(
                child: Text(
                  '名單 ${sp(r.ret)}・大盤 ${sp(r.bench)}${running ? '（抱了 ${r.days} 天，還沒滿）' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Tag(running ? (r.beat ? '暫時贏' : '暫時輸') : (r.beat ? '贏' : '輸'), r.beat ? AppColors.up : AppColors.down),
            ],
          ),
          Text(r.codes.join(' '), style: small, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
