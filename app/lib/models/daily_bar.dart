/// 日 K 資料：一檔股票某一個交易日的開高低收量。
library;

class DailyBar {
  final String date; // yyyy-MM-dd
  final double open;
  final double high;
  final double low;
  final double close;
  final int volumeLots; // 成交量，單位：張

  const DailyBar({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volumeLots,
  });

  /// 存檔用的精簡格式：[開, 高, 低, 收, 張數]，日期由外層的檔名/鍵決定。
  List<num> toRow() => [open, high, low, close, volumeLots];

  static DailyBar fromRow(String date, List<dynamic> row) => DailyBar(
        date: date,
        open: (row[0] as num).toDouble(),
        high: (row[1] as num).toDouble(),
        low: (row[2] as num).toDouble(),
        close: (row[3] as num).toDouble(),
        volumeLots: (row[4] as num).round(),
      );
}

/// 某一天全市場（上市＋上櫃）的收盤行情。
class DaySnapshot {
  final String date; // yyyy-MM-dd

  /// 那天沒開盤（假日、颱風假）就是 false，[bars] 會是空的。
  final bool trading;
  final Map<String, DailyBar> bars;

  const DaySnapshot({required this.date, required this.trading, required this.bars});

  Map<String, dynamic> toJson() => {
        'date': date,
        'trading': trading,
        'bars': {for (final e in bars.entries) e.key: e.value.toRow()},
      };

  static DaySnapshot fromJson(Map<String, dynamic> json) {
    final date = json['date'] as String;
    final raw = (json['bars'] as Map?) ?? const {};
    return DaySnapshot(
      date: date,
      trading: json['trading'] as bool? ?? raw.isNotEmpty,
      bars: {
        for (final e in raw.entries) e.key as String: DailyBar.fromRow(date, e.value as List),
      },
    );
  }
}
