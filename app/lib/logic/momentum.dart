/// 「今日雷達」的排名邏輯（沿用 stock_acc 的選股雷達）：純函式，不碰網路、
/// 不碰畫面，方便寫測試。
///
/// 重要：這是機械化的排序（今天漲跌幅、量能、離今天高點的距離），
/// 不是預測未來會不會賺錢，也不是投資建議——沒有人（包括這支程式）
/// 能保證挑出來的股票會賺錢，這份排名只是幫忙從一堆候選股裡，
/// 篩出「今天表現比較突出」的那幾檔，讓使用者自己再進一步判斷。
library;

import '../services/quote_service.dart';

class MomentumHit {
  final LiveQuote quote;
  final double score;
  final List<String> reasons;

  const MomentumHit({required this.quote, required this.score, required this.reasons});

  String get code => quote.code;
}

/// 依「今日漲跌幅」為主排序，量能和貼近當日高點當加分，算出一個分數並
/// 附上理由文字。只保留上漲的股票（下跌的股票不算「今日動能」候選）。
List<MomentumHit> rankByMomentum(List<LiveQuote> quotes) {
  final hits = <MomentumHit>[];
  for (final q in quotes) {
    if (q.changePct <= 0) continue;
    final reasons = <String>[];
    var score = q.changePct;
    reasons.add('今日上漲 ${q.changePct.toStringAsFixed(2)}%');

    final range = q.high - q.low;
    final nearHigh = range <= 0 ? true : (q.high - q.price) / range <= 0.15;
    if (nearHigh) {
      score += 1.0;
      reasons.add('股價接近今日最高點（強勢收在高檔）');
    }

    if (q.volumeLots >= 3000) {
      score += 1.0;
      reasons.add('成交量 ${q.volumeLots} 張，量能明顯放大');
    } else if (q.volumeLots >= 1000) {
      score += 0.4;
      reasons.add('成交量 ${q.volumeLots} 張');
    }

    if (q.open > 0 && q.price > q.open) {
      score += 0.3;
      reasons.add('開高走高');
    }

    hits.add(MomentumHit(quote: q, score: score, reasons: reasons));
  }
  hits.sort((a, b) => b.score.compareTo(a.score));
  return hits;
}
