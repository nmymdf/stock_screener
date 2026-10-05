/// 長期分析的整條流程：讀資料包 → 建精簡資料 → 每個檢視日評分 → 組合回測（幾種設定比較）
/// → 因子研究 → 最新一天的評分、市場曝險、理想組合。App（背景 isolate）和 GitHub Actions 共用。
library;

import 'dart:io';

import 'exposure.dart';
import 'factors.dart';
import 'lt_data.dart';
import 'pack.dart';
import 'portfolio.dart';
import 'research.dart';

/// 從資料夾讀資料包：lt-YYYY（各年）、recent（最近 30 天）、營收、除權息、國際指標。
/// [extraDays] 是資料包之後的日子（例如 App 今天直接抓到的收盤），依日期接在最後面。
LtData loadPackDir(String dir, {List<PackDay> extraDays = const []}) {
  DividendData? div;
  RevenueData? rev;
  IntlData? intl;
  Map<String, dynamic>? readGz(String name) {
    final f = File('$dir/$name');
    if (!f.existsSync()) return null;
    try {
      return decodeGz(f.readAsBytesSync());
    } catch (_) {
      return null; // 壞掉的檔案當作沒有，下次更新會重抓
    }
  }

  final dj = readGz('dividends.json.gz');
  if (dj != null) div = DividendData.fromJson(dj);
  final rj = readGz('revenue.json.gz');
  if (rj != null) rev = RevenueData.fromJson(rj);
  final ij = readGz('intl.json.gz');
  if (ij != null) intl = IntlData.fromJson(ij);
  final b = LtDataBuilder(dividends: div);
  final re = RegExp(r'lt-(\d{4})\.json\.gz$');
  final years = <int>[];
  final d = Directory(dir);
  if (d.existsSync()) {
    for (final f in d.listSync().whereType<File>()) {
      final m = re.firstMatch(f.path);
      if (m != null) years.add(int.parse(m.group(1)!));
    }
  }
  years.sort();
  for (final y in years) {
    final j = readGz('lt-$y.json.gz');
    if (j != null) b.addLtYear(j);
  }
  final recent = readGz('recent.json.gz');
  if (recent != null) {
    final rp = RecentPack.fromJson(recent);
    b.names.addAll({...rp.names, ...b.names});
    for (final day in rp.days) {
      b.addDay(day);
    }
  }
  for (final day in extraDays) {
    b.addDay(day, knownOnly: true);
  }
  return b.build(revenue: rev, dividends: div, intl: intl);
}

class LtVariant {
  final String label;
  final LtConfig cfg;
  final PerfStats stats;
  const LtVariant(this.label, this.cfg, this.stats);
}

class LtResult {
  final LtData data;
  final ScoreBook book;

  /// 最新一天的完整評分。
  final SampleScores live;
  final ExposureState exposure;

  /// 預設設定的回測（也是「理想組合」目前的持股）。
  final SimResult sim;
  final List<LtVariant> variants;
  final FactorResearch research;

  /// 現在如果檢視一次會怎麼調整（今天不是檢視日時，給參考）。
  final LtDecision? preview;
  final Duration elapsed;

  const LtResult({
    required this.data,
    required this.book,
    required this.live,
    required this.exposure,
    required this.sim,
    required this.variants,
    required this.research,
    required this.preview,
    required this.elapsed,
  });

  String? get date => data.lastDate;

  LtScore? scoreOf(String code) {
    final si = data.index[code];
    return si == null ? null : live.of(si);
  }

  /// 某檔股票各檢視日的總分百分位（分數走勢）。
  List<(String, double)> pctHistory(String code) {
    final si = data.index[code];
    if (si == null) return const [];
    return [
      for (var s = 0; s < data.samples.length; s++)
        if (book.scored(s, si)) (data.samples[s].date, book.pct[book.at(s, si)].toDouble()),
    ];
  }
}

/// 跑整條長期分析。[cfg] 是使用者選的組合設定；另外會跑幾種設定給回測頁比較。
LtResult runLtAnalysis(LtData data, {LtConfig cfg = const LtConfig(), bool variants = true}) {
  final sw = Stopwatch()..start();
  if (data.samples.isEmpty) throw StateError('還沒有長期資料，請先下載資料包');
  final engine = FactorEngine(data);
  final book = ScoreBook(data.samples.length, data.stocks.length);
  SampleScores? live;
  for (var s = 0; s < data.samples.length; s++) {
    final sc = engine.score(s);
    book.put(sc);
    if (s == data.samples.length - 1) live = sc;
  }
  final exposure = ExposureEngine(data);
  final sim = PortfolioSim(data, book, exposure, cfg);
  final result = sim.run();
  final out = <LtVariant>[LtVariant('目前設定', cfg, result.stats)];
  if (variants) {
    for (final (label, c) in [
      ('一直滿倉（不看環境）', cfg.copyWith(exposure: ExposureMode.none)),
      ('看台股環境調整', cfg.copyWith(exposure: ExposureMode.local)),
      ('看台股＋國際環境調整', cfg.copyWith(exposure: ExposureMode.localIntl)),
      ('10 檔', cfg.copyWith(size: 10)),
      ('15 檔', cfg.copyWith(size: 15)),
      ('每月最多換 3 檔', cfg.copyWith(maxChanges: 3)),
      ('全部選股（沒有大盤核心）', cfg.copyWith(coreWeight: 0)),
      ('大盤核心 30%＋選股 70%', cfg.copyWith(coreWeight: 0.3)),
      ('大盤核心 50%＋選股 50%', cfg.copyWith(coreWeight: 0.5)),
    ]) {
      if (c.exposure == cfg.exposure &&
          c.size == cfg.size &&
          c.maxChanges == cfg.maxChanges &&
          c.coreWeight == cfg.coreWeight) {
        continue;
      }
      try {
        out.add(LtVariant(label, c, PortfolioSim(data, book, exposure, c).run().stats));
      } catch (_) {}
    }
  }
  final research = factorResearch(data, book, from: cfg.startDate);
  final liveSc = live!;
  final exp = exposure.at(liveSc.t, liveSc.breadth, mode: cfg.exposure);
  LtDecision? preview;
  if (result.pending == null && liveSc.sample.live) {
    preview = sim.decide(liveSc);
  }
  return LtResult(
    data: data,
    book: book,
    live: liveSc,
    exposure: exp,
    sim: result,
    variants: out,
    research: research,
    preview: preview,
    elapsed: sw.elapsed,
  );
}
