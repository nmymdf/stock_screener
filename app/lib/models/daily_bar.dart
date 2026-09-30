/// 日 K 資料：一檔股票某一個交易日的開高低收量。
library;

class DailyBar {
  final String date; // yyyy-MM-dd
  final double open;
  final double high;
  final double low;
  final double close;
  final int volumeLots; // 成交量，單位：張

  /// 交易所公布的「漲跌價差」（帶正負號），是跟當天「參考價」比，不是跟前一天
  /// 收盤比。除權息那天參考價會比前一天收盤低，兩者對不起來，就是用這個差異
  /// 偵測除權息、還原股價。舊版存檔沒有這個欄位，是 null。
  final double? change;

  const DailyBar({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volumeLots,
    this.change,
  });

  /// 當天的參考價（漲跌停、除權息都以它為準）；不知道就是 null。
  double? get refPrice => change == null ? null : close - change!;

  DailyBar scaled(double f) => DailyBar(
    date: date,
    open: open * f,
    high: high * f,
    low: low * f,
    close: close * f,
    volumeLots: volumeLots,
    change: change == null ? null : change! * f,
  );

  /// 存檔用的精簡格式：[開, 高, 低, 收, 張數, 漲跌價差?]，日期由外層決定。
  List<num> toRow() => [open, high, low, close, volumeLots, ?change];

  static DailyBar fromRow(String date, List<dynamic> row) => DailyBar(
    date: date,
    open: (row[0] as num).toDouble(),
    high: (row[1] as num).toDouble(),
    low: (row[2] as num).toDouble(),
    close: (row[3] as num).toDouble(),
    volumeLots: (row[4] as num).round(),
    change: row.length > 5 ? (row[5] as num?)?.toDouble() : null,
  );
}

/// 某一天全市場（上市＋上櫃）的收盤行情。
class DaySnapshot {
  final String date; // yyyy-MM-dd

  /// 那天沒開盤（假日、颱風假）就是 false，[bars] 會是空的。
  final bool trading;
  final Map<String, DailyBar> bars;

  /// 發行量加權股價指數收盤；抓不到是 null。
  final double? taiex;

  const DaySnapshot({required this.date, required this.trading, required this.bars, this.taiex});

  Map<String, dynamic> toJson() => {
    'date': date,
    'trading': trading,
    'taiex': ?taiex,
    'bars': {for (final e in bars.entries) e.key: e.value.toRow()},
  };

  static DaySnapshot fromJson(Map<String, dynamic> json) {
    final date = json['date'] as String;
    final raw = (json['bars'] as Map?) ?? const {};
    return DaySnapshot(
      date: date,
      trading: json['trading'] as bool? ?? raw.isNotEmpty,
      taiex: (json['taiex'] as num?)?.toDouble(),
      bars: {for (final e in raw.entries) e.key as String: DailyBar.fromRow(date, e.value as List)},
    );
  }
}
