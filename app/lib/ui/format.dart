/// 數字的顯示格式：千分位、正數加「+」。
library;

import 'package:intl/intl.dart';

final _int = NumberFormat.decimalPattern('zh_TW');
final _dec2 = NumberFormat('#,##0.00', 'zh_TW');

String f0(num n) => _int.format(n.round());
String f2(num n) => _dec2.format(n);

/// 已經是百分比的數字（例如 3.25 代表 3.25%），加正負號顯示。
String pctTxt(num? v) {
  if (v == null) return '—';
  return '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}%';
}

String optF2(num? v) => v == null ? '—' : f2(v);
