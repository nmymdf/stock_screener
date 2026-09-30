/// 市場環境引擎（規格書 §2）：用全市場每一檔股票的日 K 算市場廣度，再合成
/// Market Score（0～100）和五種市場狀態。目的不是預測指數點數，而是決定
/// 「現在適不適合積極做多、最多該放多少部位」。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../ta.dart';

enum Regime { strongBull, bull, range, weak, bear }

extension RegimeInfo on Regime {
  String get label => switch (this) {
    Regime.strongBull => '強勢多頭',
    Regime.bull => '一般多頭',
    Regime.range => '震盪',
    Regime.weak => '弱勢',
    Regime.bear => '空頭／極端風險',
  };

  /// 規格書 §2.5 建議最大總曝險。
  String get exposure => switch (this) {
    Regime.strongBull => '80–90%',
    Regime.bull => '60–70%',
    Regime.range => '30–40%',
    Regime.weak => '10–20%',
    Regime.bear => '0–10%',
  };

  String get attitude => switch (this) {
    Regime.strongBull => '可以積極使用突破與趨勢策略。',
    Regime.bull => '正常交易，保留一部分現金。',
    Regime.range => '降低追價、提高條件門檻；均值回歸型（D）只在這種盤勢啟用。',
    Regime.weak => '只做少量、短週期，嚴格風控。',
    Regime.bear => '原則上停止一般多單，系統不會推薦任何新進場。',
  };

  /// 推薦門檻：市場越弱，個股總分要越高才推薦（規格書 §2.5「提高條件門檻」）。
  double get minTotalScore => switch (this) {
    Regime.strongBull => 55,
    Regime.bull => 60,
    Regime.range => 65,
    Regime.weak => 70,
    Regime.bear => 101,
  };
}

Regime regimeOf(double score) {
  if (score >= 80) return Regime.strongBull;
  if (score >= 65) return Regime.bull;
  if (score >= 50) return Regime.range;
  if (score >= 35) return Regime.weak;
  return Regime.bear;
}

/// 某一天的市場廣度統計（只算一般股票，不含 ETF／ETN／特別股）。
class BreadthDay {
  final String date;
  final int total, adv, dec, limitUp, limitDown;
  final int above20, n20, above60, n60, above120, n120, above240, n240;
  final int nh20, nl20, nh60, nl60, nh250, nl250;
  final int largeAbove20, largeN20, smallAbove20, smallN20;
  final double ewIndex, ewTwse, ewTpex; // 等權指數（起點 100）
  final double? taiex;

  const BreadthDay({
    required this.date,
    required this.total,
    required this.adv,
    required this.dec,
    required this.limitUp,
    required this.limitDown,
    required this.above20,
    required this.n20,
    required this.above60,
    required this.n60,
    required this.above120,
    required this.n120,
    required this.above240,
    required this.n240,
    required this.nh20,
    required this.nl20,
    required this.nh60,
    required this.nl60,
    required this.nh250,
    required this.nl250,
    required this.largeAbove20,
    required this.largeN20,
    required this.smallAbove20,
    required this.smallN20,
    required this.ewIndex,
    required this.ewTwse,
    required this.ewTpex,
    required this.taiex,
  });

  double? pct(int a, int n) => n < 30 ? null : a / n;
  double? get pctAbove20 => pct(above20, n20);
  double? get pctAbove60 => pct(above60, n60);
  double? get pctAbove120 => pct(above120, n120);
  double? get pctAbove240 => pct(above240, n240);
}

/// 逐檔累加廣度計數，最後產生每天的 [BreadthDay]。
class BreadthBuilder {
  final List<String> dates;
  final int _n;
  final Int32List total, adv, dec, lu, ld;
  final Int32List a20, n20, a60, n60, a120, n120, a240, n240;
  final Int32List nh20, nl20, nh60, nl60, nh250, nl250;
  final Int32List la20, ln20, sa20, sn20;
  final Float64List ret, retTwse, retTpex;
  final Int32List cnt, cntTwse, cntTpex;

  BreadthBuilder(this.dates)
    : _n = dates.length,
      total = Int32List(dates.length),
      adv = Int32List(dates.length),
      dec = Int32List(dates.length),
      lu = Int32List(dates.length),
      ld = Int32List(dates.length),
      a20 = Int32List(dates.length),
      n20 = Int32List(dates.length),
      a60 = Int32List(dates.length),
      n60 = Int32List(dates.length),
      a120 = Int32List(dates.length),
      n120 = Int32List(dates.length),
      a240 = Int32List(dates.length),
      n240 = Int32List(dates.length),
      nh20 = Int32List(dates.length),
      nl20 = Int32List(dates.length),
      nh60 = Int32List(dates.length),
      nl60 = Int32List(dates.length),
      nh250 = Int32List(dates.length),
      nl250 = Int32List(dates.length),
      la20 = Int32List(dates.length),
      ln20 = Int32List(dates.length),
      sa20 = Int32List(dates.length),
      sn20 = Int32List(dates.length),
      ret = Float64List(dates.length),
      retTwse = Float64List(dates.length),
      retTpex = Float64List(dates.length),
      cnt = Int32List(dates.length),
      cntTwse = Int32List(dates.length),
      cntTpex = Int32List(dates.length);

  /// [dateIdx]：這檔股票每根 K 棒對應到全市場日期的位置。
  void add(StockSeries s, List<int> dateIdx, {required bool large, required bool tpex}) {
    final c = s.close;
    for (var i = 1; i < s.length; i++) {
      final d = dateIdx[i];
      total[d]++;
      final ch = c[i] - c[i - 1];
      if (ch > 0) {
        adv[d]++;
      } else if (ch < 0) {
        dec[d]++;
      }
      if (s.isLimitUp(i)) lu[d]++;
      if (s.isLimitDown(i)) ld[d]++;
      if (ok(s.sma20[i])) {
        n20[d]++;
        final above = c[i] > s.sma20[i];
        if (above) a20[d]++;
        if (large) {
          ln20[d]++;
          if (above) la20[d]++;
        } else {
          sn20[d]++;
          if (above) sa20[d]++;
        }
      }
      if (ok(s.sma60[i])) {
        n60[d]++;
        if (c[i] > s.sma60[i]) a60[d]++;
      }
      if (ok(s.sma120[i])) {
        n120[d]++;
        if (c[i] > s.sma120[i]) a120[d]++;
      }
      if (ok(s.sma240[i])) {
        n240[d]++;
        if (c[i] > s.sma240[i]) a240[d]++;
      }
      void hl(int w, Int32List nh, Int32List nl) {
        if (i < w) return;
        if (c[i] > maxIn(c, i - w, i - 1)) nh[d]++;
        if (c[i] < minIn(c, i - w, i - 1)) nl[d]++;
      }

      hl(20, nh20, nl20);
      hl(60, nh60, nl60);
      hl(250, nh250, nl250);

      // 等權指數：每檔當天漲跌幅的平均（截在 ±11%，避免資料錯誤一筆拉歪）
      if (c[i - 1] > 0) {
        final r = (c[i] / c[i - 1] - 1).clamp(-0.11, 0.11);
        ret[d] += r;
        cnt[d]++;
        if (tpex) {
          retTpex[d] += r;
          cntTpex[d]++;
        } else {
          retTwse[d] += r;
          cntTwse[d]++;
        }
      }
    }
  }

  List<BreadthDay> build(Map<String, double> taiex) {
    final out = <BreadthDay>[];
    var ew = 100.0, ewT = 100.0, ewO = 100.0;
    for (var d = 0; d < _n; d++) {
      if (cnt[d] > 0) ew *= 1 + ret[d] / cnt[d];
      if (cntTwse[d] > 0) ewT *= 1 + retTwse[d] / cntTwse[d];
      if (cntTpex[d] > 0) ewO *= 1 + retTpex[d] / cntTpex[d];
      out.add(
        BreadthDay(
          date: dates[d],
          total: total[d],
          adv: adv[d],
          dec: dec[d],
          limitUp: lu[d],
          limitDown: ld[d],
          above20: a20[d],
          n20: n20[d],
          above60: a60[d],
          n60: n60[d],
          above120: a120[d],
          n120: n120[d],
          above240: a240[d],
          n240: n240[d],
          nh20: nh20[d],
          nl20: nl20[d],
          nh60: nh60[d],
          nl60: nl60[d],
          nh250: nh250[d],
          nl250: nl250[d],
          largeAbove20: la20[d],
          largeN20: ln20[d],
          smallAbove20: sa20[d],
          smallN20: sn20[d],
          ewIndex: ew,
          ewTwse: ewT,
          ewTpex: ewO,
          taiex: taiex[dates[d]],
        ),
      );
    }
    return out;
  }
}

/// Market Score 的一個組成項目。
class MarketComponent {
  final String name;
  final double weight;
  final double? value; // 0～1；null = 資料不足、不列入計算
  final String detail;
  final String explain;
  const MarketComponent(this.name, this.weight, this.value, this.detail, this.explain);
}

class MarketDay {
  final BreadthDay breadth;
  final double? score;
  final List<MarketComponent> components;
  final List<String> warnings;
  final List<String> notes;
  final bool usesTaiex;

  const MarketDay(this.breadth, this.score, this.components, this.warnings, this.notes, this.usesTaiex);

  String get date => breadth.date;
  Regime? get regime => score == null ? null : regimeOf(score!);
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
String _p(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(0)}%';

/// 算每一天的 Market Score。前面資料不足的日子 score 是 null。
List<MarketDay> scoreMarket(List<BreadthDay> days) {
  final n = days.length;
  // 指數：有加權指數就用加權指數，缺的話用等權指數（兩者的差異在畫面上會標示）
  final taiexOk = days.where((d) => d.taiex != null).length >= n * 0.9 && n > 0;
  final idx = Float64List(n);
  for (var i = 0; i < n; i++) {
    idx[i] = taiexOk ? (days[i].taiex ?? (i > 0 ? idx[i - 1] : days[i].ewIndex)) : days[i].ewIndex;
  }
  final ma20 = smaSeries(idx, 20), ma60 = smaSeries(idx, 60), ma120 = smaSeries(idx, 120), ma240 = smaSeries(idx, 240);

  final out = <MarketDay>[];
  for (var t = 0; t < n; t++) {
    final b = days[t];
    final comps = <MarketComponent>[];
    final warnings = <String>[];
    final notes = <String>[];

    // 1. 多週期大盤趨勢（§2.1，用日線資料近似：20 日≈日線、60 日≈週線、240 日≈月線）
    var trendPts = 0.0, trendMax = 0.0;
    final trendDetail = <String>[];
    void item(bool? cond, double pts, String label) {
      if (cond == null) return;
      trendMax += pts;
      if (cond) trendPts += pts;
      trendDetail.add('${cond ? '✓' : '✗'} $label');
    }

    item(ok(ma20[t]) ? idx[t] > ma20[t] : null, 5, '日線：指數在 20 日線上');
    item(t >= 5 && ok(ma20[t]) && ok(ma20[t - 5]) ? ma20[t] > ma20[t - 5] : null, 5, '日線：20 日線上揚');
    item(ok(ma60[t]) ? idx[t] > ma60[t] : null, 5, '週線：指數在 60 日線上');
    item(t >= 10 && ok(ma60[t]) && ok(ma60[t - 10]) ? ma60[t] > ma60[t - 10] : null, 5, '週線：60 日線上揚');
    final longMa = ok(ma240[t]) ? ma240 : ma120;
    item(ok(longMa[t]) ? idx[t] > longMa[t] : null, 5, '月線：指數在 ${identical(longMa, ma240) ? 240 : 120} 日線上');
    comps.add(
      MarketComponent(
        '大盤多週期趨勢',
        25,
        trendMax < 10 ? null : trendPts / trendMax,
        trendDetail.join('\n'),
        '用${taiexOk ? '加權指數' : '全市場等權指數'}的日、週、月級別均線判斷背景方向。',
      ),
    );

    // 2～4. 站上均線的股票比例（§2.2）
    comps.add(
      MarketComponent(
        '站上 20 日線比例',
        15,
        b.pctAbove20 == null ? null : _clamp01((b.pctAbove20! - 0.2) / 0.5),
        _p(b.pctAbove20),
        '短期廣度：20% 以下給 0 分，70% 以上給滿分。',
      ),
    );
    comps.add(
      MarketComponent(
        '站上 60 日線比例',
        15,
        b.pctAbove60 == null ? null : _clamp01((b.pctAbove60! - 0.2) / 0.5),
        _p(b.pctAbove60),
        '中期廣度：多數股票站上季線，代表上漲不是只靠少數股票。',
      ),
    );
    final longs = [b.pctAbove120, b.pctAbove240].whereType<double>().toList();
    comps.add(
      MarketComponent(
        '站上 120／240 日線比例',
        10,
        longs.isEmpty ? null : _clamp01((longs.reduce((a, c) => a + c) / longs.length - 0.2) / 0.5),
        '120 日 ${_p(b.pctAbove120)}／240 日 ${_p(b.pctAbove240)}',
        '長期廣度，需要半年～一年的資料。',
      ),
    );

    // 5. 漲跌家數（10 日累計）
    if (t >= 9) {
      var a = 0, d = 0;
      for (var k = t - 9; k <= t; k++) {
        a += days[k].adv;
        d += days[k].dec;
      }
      final r = a + d == 0 ? 0.5 : a / (a + d);
      comps.add(
        MarketComponent(
          '上漲／下跌家數（10 日）',
          10,
          _clamp01((r - 0.35) / 0.3),
          '上漲 $a／下跌 $d（${_p(r)}）',
          '上漲家數占比 35% 以下給 0 分，65% 以上給滿分。',
        ),
      );
    } else {
      comps.add(const MarketComponent('上漲／下跌家數（10 日）', 10, null, '—', '需要 10 天資料。'));
    }

    // 6. 新高／新低家數（10 日累計，20 日新高低）
    if (t >= 9 && t >= 20) {
      var h = 0, l = 0;
      for (var k = t - 9; k <= t; k++) {
        h += days[k].nh20;
        l += days[k].nl20;
      }
      comps.add(
        MarketComponent(
          '創新高／新低家數（10 日）',
          15,
          h + l == 0 ? 0.5 : h / (h + l),
          '20 日新高 $h／新低 $l',
          '創新高的股票多於創新低，代表強勢在擴散。',
        ),
      );
    } else {
      comps.add(const MarketComponent('創新高／新低家數（10 日）', 15, null, '—', '需要 30 天資料。'));
    }

    // 7. 漲停／跌停（5 日累計）
    if (t >= 4) {
      var u = 0, d = 0;
      for (var k = t - 4; k <= t; k++) {
        u += days[k].limitUp;
        d += days[k].limitDown;
      }
      comps.add(MarketComponent('漲停／跌停家數（5 日）', 10, (u + 1) / (u + d + 2), '漲停 $u／跌停 $d', '跌停家數明顯增加通常是恐慌訊號。'));
    } else {
      comps.add(const MarketComponent('漲停／跌停家數（5 日）', 10, null, '—', '需要 5 天資料。'));
    }

    final avail = comps.where((c) => c.value != null);
    final wSum = avail.fold(0.0, (a, c) => a + c.weight);
    double? score = wSum < 40 ? null : avail.fold(0.0, (a, c) => a + c.weight * c.value!) / wSum * 100;

    // §2.2 重要原則：指數強但廣度差 → 降低曝險
    if (score != null && ok(ma20[t]) && idx[t] > ma20[t] && (b.pctAbove20 ?? 1) < 0.4) {
      score = math.max(0, score - 8);
      warnings.add(
        '指數在 20 日線上，但只有 ${_p(b.pctAbove20)} 的股票站上 20 日線——漲勢集中在少數股票，'
        '市場並不健康，分數已扣 8 分。',
      );
    }
    // 大型股 vs 中小型股同步程度
    final lp = b.largeN20 >= 30 ? b.largeAbove20 / b.largeN20 : null;
    final sp = b.smallN20 >= 30 ? b.smallAbove20 / b.smallN20 : null;
    if (lp != null && sp != null) {
      notes.add(
        '大型股（成交值前 150）站上 20 日線 ${_p(lp)}，中小型股 ${_p(sp)}'
        '${(lp - sp).abs() > 0.25 ? '——兩者落差大，行情不同步' : '，大致同步'}。',
      );
      if ((lp - sp).abs() > 0.25) warnings.add('大型股與中小型股強弱落差超過 25 個百分點，行情不同步。');
    }
    // 上市 vs 上櫃是否同方向（20 日等權報酬）
    if (t >= 20) {
      final rt = (b.ewTwse / days[t - 20].ewTwse - 1) * 100;
      final ro = (b.ewTpex / days[t - 20].ewTpex - 1) * 100;
      final same = rt.sign == ro.sign;
      notes.add(
        '近 20 日等權報酬：上市 ${rt.toStringAsFixed(1)}%、上櫃 ${ro.toStringAsFixed(1)}%，'
        '${same ? '同方向' : '方向相反'}。',
      );
      if (!same) warnings.add('上市與上櫃近 20 日走勢方向相反。');
    }
    out.add(MarketDay(b, score, comps, warnings, notes, taiexOk));
  }
  return out;
}
