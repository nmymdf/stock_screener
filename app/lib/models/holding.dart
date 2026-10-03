/// 我的持股：買進、賣出紀錄，加上持有方式（決定停損和出場規則）。
library;

/// 持有方式：每一種用不同的停損與出場規則（見 logic/holding_eval.dart）。
enum HoldStyle { short, swing, long, custom }

extension HoldStyleInfo on HoldStyle {
  String get label => switch (this) {
    HoldStyle.short => '短線',
    HoldStyle.swing => '波段',
    HoldStyle.long => '長期',
    HoldStyle.custom => '自己設定',
  };

  /// 對應的持有期間等級（自己設定沒有）。
  int? get durationClass => switch (this) {
    HoldStyle.short => 1,
    HoldStyle.swing => 2,
    HoldStyle.long => 3,
    HoldStyle.custom => null,
  };

  String get period => switch (this) {
    HoldStyle.short => '1～3 週',
    HoldStyle.swing => '1～3 個月',
    HoldStyle.long => '一季以上',
    HoldStyle.custom => '自訂',
  };

  String get rules => switch (this) {
    HoldStyle.short =>
      '停損：進場價 − 2 ATR（或推薦時的停損）。漲到 +1R 停損拉到成本（保本）；到 2R（或推薦目標）先賣一半，'
          '剩下用「最高價 − 3 ATR」移動停利；買進 10 個交易日還沒有 +1R 就時間停損。',
    HoldStyle.swing =>
      '停損：進場價 − 2.5 ATR（或推薦時的停損）。漲到 +1R 停損拉到成本（保本），之後用「最高價 − 3 ATR」'
          '移動停利一路抱住，不設固定目標、不設時間停損。',
    HoldStyle.long =>
      '停損：虧損 15%。趨勢出場：收盤連續 3 天跌破 60 日均線（季線）且季線往下彎；有一年資料時，'
          '跌破 240 日均線（年線）也提醒。不主動停利、不設時間停損。',
    HoldStyle.custom => '用你自己填的停損價和目標價：收盤跌破停損就停損，碰到目標就提醒獲利了結。',
  };
}

class BuyLot {
  final String date; // yyyy-MM-dd
  final double price;
  final int shares;
  const BuyLot(this.date, this.price, this.shares);

  Map<String, dynamic> toJson() => {'date': date, 'price': price, 'shares': shares};
  static BuyLot fromJson(Map<String, dynamic> j) =>
      BuyLot(j['date'] as String, (j['price'] as num).toDouble(), (j['shares'] as num).round());
}

class SellLot {
  final String date;
  final double price;
  final int shares;
  final String? reason;
  const SellLot(this.date, this.price, this.shares, {this.reason});

  Map<String, dynamic> toJson() => {'date': date, 'price': price, 'shares': shares, 'reason': ?reason};
  static SellLot fromJson(Map<String, dynamic> j) => SellLot(
    j['date'] as String,
    (j['price'] as num).toDouble(),
    (j['shares'] as num).round(),
    reason: j['reason'] as String?,
  );
}

class Holding {
  final String id;
  final String code;
  final HoldStyle style;
  final List<BuyLot> buys;
  final List<SellLot> sells;

  /// 自己設定的停損／目標（「自己設定」方式一定要有停損；其他方式填了停損，
  /// 會跟規則算出來的取比較高的那個——停損只能往上調）。
  final double? manualStop;
  final double? manualTarget;

  /// 從推薦清單帶進來的計畫（策略代號、當時的停損和目標、推薦理由）。
  final String? strategy;
  final double? planStop;
  final double? planTarget;
  final String? reason;
  final String? note;

  /// 買進當下的判斷（最終版 §14 Thesis Lifecycle 的 Original Thesis）：
  /// 機會類型、預估持有期間 D1～D3 與信心度、主要理由。
  final String? opportunity;
  final int? duration;
  final String? confidence;
  final List<String> thesis;

  const Holding({
    required this.id,
    required this.code,
    required this.style,
    required this.buys,
    this.sells = const [],
    this.manualStop,
    this.manualTarget,
    this.strategy,
    this.planStop,
    this.planTarget,
    this.reason,
    this.note,
    this.opportunity,
    this.duration,
    this.confidence,
    this.thesis = const [],
  });

  int get boughtShares => buys.fold(0, (a, b) => a + b.shares);
  int get soldShares => sells.fold(0, (a, b) => a + b.shares);
  int get shares => boughtShares - soldShares;
  bool get closed => shares <= 0;

  /// 平均成本（每股，不含手續費）。
  double get avgCost {
    final n = boughtShares;
    if (n == 0) return 0;
    return buys.fold(0.0, (a, b) => a + b.price * b.shares) / n;
  }

  /// 某一天收盤時持有的股數。
  int sharesAt(String date) =>
      buys.where((b) => b.date.compareTo(date) <= 0).fold(0, (a, b) => a + b.shares) -
      sells.where((s) => s.date.compareTo(date) <= 0).fold(0, (a, b) => a + b.shares);

  String get firstBuyDate => (buys.map((b) => b.date).toList()..sort()).first;
  String? get lastSellDate => sells.isEmpty ? null : (sells.map((s) => s.date).toList()..sort()).last;

  Holding copyWith({
    HoldStyle? style,
    List<BuyLot>? buys,
    List<SellLot>? sells,
    Object? manualStop = _keep,
    Object? manualTarget = _keep,
    Object? note = _keep,
  }) => Holding(
    id: id,
    code: code,
    style: style ?? this.style,
    buys: buys ?? this.buys,
    sells: sells ?? this.sells,
    manualStop: identical(manualStop, _keep) ? this.manualStop : manualStop as double?,
    manualTarget: identical(manualTarget, _keep) ? this.manualTarget : manualTarget as double?,
    strategy: strategy,
    planStop: planStop,
    planTarget: planTarget,
    reason: reason,
    note: identical(note, _keep) ? this.note : note as String?,
    opportunity: opportunity,
    duration: duration,
    confidence: confidence,
    thesis: thesis,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'style': style.name,
    'buys': [for (final b in buys) b.toJson()],
    'sells': [for (final s in sells) s.toJson()],
    'manualStop': ?manualStop,
    'manualTarget': ?manualTarget,
    'strategy': ?strategy,
    'planStop': ?planStop,
    'planTarget': ?planTarget,
    'reason': ?reason,
    'note': ?note,
    'opportunity': ?opportunity,
    'duration': ?duration,
    'confidence': ?confidence,
    if (thesis.isNotEmpty) 'thesis': thesis,
  };

  static Holding fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return Holding(
      id: j['id'] as String,
      code: j['code'] as String,
      style: HoldStyle.values.firstWhere((s) => s.name == j['style'], orElse: () => HoldStyle.swing),
      buys: [for (final b in (j['buys'] as List? ?? const [])) BuyLot.fromJson(b as Map<String, dynamic>)],
      sells: [for (final s in (j['sells'] as List? ?? const [])) SellLot.fromJson(s as Map<String, dynamic>)],
      manualStop: d('manualStop'),
      manualTarget: d('manualTarget'),
      strategy: j['strategy'] as String?,
      planStop: d('planStop'),
      planTarget: d('planTarget'),
      reason: j['reason'] as String?,
      note: j['note'] as String?,
      opportunity: j['opportunity'] as String?,
      duration: (j['duration'] as num?)?.round(),
      confidence: j['confidence'] as String?,
      thesis: [for (final x in (j['thesis'] as List? ?? const [])) x as String],
    );
  }
}

const Object _keep = Object();
