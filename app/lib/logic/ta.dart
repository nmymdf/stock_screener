/// 技術指標的「整條序列」版本（規格書 §7、§8）：EMA、ATR、ADX/DI、MACD、RSI、
/// 布林帶寬、KD、OBV、區間最高最低。
///
/// 為了省記憶體（全市場兩千多檔 × 一年的日 K），一律用 [Float64List]，
/// 資料不足、還算不出來的位置放 NaN，用 [ok] 判斷。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../models/daily_bar.dart';

bool ok(double v) => !v.isNaN;

Float64List _nan(int n) => Float64List(n)..fillRange(0, n, double.nan);

Float64List smaSeries(List<double> v, int n) {
  final out = _nan(v.length);
  var sum = 0.0;
  for (var i = 0; i < v.length; i++) {
    sum += v[i];
    if (i >= n) sum -= v[i - n];
    if (i >= n - 1) out[i] = sum / n;
  }
  return out;
}

/// 指數移動平均；第一個值用前 n 筆的簡單平均當起點。
Float64List emaSeries(List<double> v, int n) {
  final out = _nan(v.length);
  if (v.length < n) return out;
  var e = 0.0;
  for (var i = 0; i < n; i++) {
    e += v[i];
  }
  e /= n;
  out[n - 1] = e;
  final k = 2 / (n + 1);
  for (var i = n; i < v.length; i++) {
    e = v[i] * k + e * (1 - k);
    out[i] = e;
  }
  return out;
}

/// Wilder 平滑（ATR、ADX、RSI 用的平滑法）。
Float64List _wilder(List<double> v, int n, {int start = 0}) {
  final out = _nan(v.length);
  if (v.length - start < n) return out;
  var s = 0.0;
  for (var i = start; i < start + n; i++) {
    s += v[i];
  }
  s /= n;
  out[start + n - 1] = s;
  for (var i = start + n; i < v.length; i++) {
    s = (s * (n - 1) + v[i]) / n;
    out[i] = s;
  }
  return out;
}

Float64List trueRange(List<double> h, List<double> l, List<double> c) {
  final out = Float64List(c.length);
  for (var i = 0; i < c.length; i++) {
    if (i == 0) {
      out[i] = h[i] - l[i];
    } else {
      out[i] = math.max(h[i] - l[i], math.max((h[i] - c[i - 1]).abs(), (l[i] - c[i - 1]).abs()));
    }
  }
  return out;
}

Float64List atrSeries(List<double> h, List<double> l, List<double> c, {int n = 14}) =>
    _wilder(trueRange(h, l, c), n, start: 1);

class AdxSeries {
  final Float64List adx, diPlus, diMinus;
  AdxSeries(this.adx, this.diPlus, this.diMinus);
}

/// ADX + DI（規格書 §7.1：判斷趨勢強度與方向）。
AdxSeries adxSeries(List<double> h, List<double> l, List<double> c, {int n = 14}) {
  final len = c.length;
  final pdm = Float64List(len), mdm = Float64List(len);
  for (var i = 1; i < len; i++) {
    final up = h[i] - h[i - 1];
    final down = l[i - 1] - l[i];
    pdm[i] = up > down && up > 0 ? up : 0;
    mdm[i] = down > up && down > 0 ? down : 0;
  }
  final tr = _wilder(trueRange(h, l, c), n, start: 1);
  final sp = _wilder(pdm, n, start: 1);
  final sm = _wilder(mdm, n, start: 1);
  final dip = _nan(len), dim = _nan(len), dx = _nan(len);
  for (var i = 0; i < len; i++) {
    if (!ok(tr[i]) || tr[i] == 0) continue;
    dip[i] = 100 * sp[i] / tr[i];
    dim[i] = 100 * sm[i] / tr[i];
    final s = dip[i] + dim[i];
    dx[i] = s == 0 ? 0 : 100 * (dip[i] - dim[i]).abs() / s;
  }
  final firstDx = dx.indexWhere(ok);
  final adx = firstDx < 0 ? _nan(len) : _wilder(dx, n, start: firstDx);
  return AdxSeries(adx, dip, dim);
}

class MacdSeries {
  final Float64List macd, signal, hist;
  MacdSeries(this.macd, this.signal, this.hist);
}

MacdSeries macdSeries(List<double> c, {int fast = 12, int slow = 26, int signal = 9}) {
  final ef = emaSeries(c, fast), es = emaSeries(c, slow);
  final len = c.length;
  final m = _nan(len);
  for (var i = 0; i < len; i++) {
    if (ok(ef[i]) && ok(es[i])) m[i] = ef[i] - es[i];
  }
  final first = m.indexWhere(ok);
  final sig = _nan(len), hist = _nan(len);
  if (first >= 0 && len - first >= signal) {
    final e = emaSeries(m.sublist(first), signal);
    for (var i = 0; i < e.length; i++) {
      sig[first + i] = e[i];
      if (ok(e[i])) hist[first + i] = m[first + i] - e[i];
    }
  }
  return MacdSeries(m, sig, hist);
}

Float64List rsiSeries(List<double> c, {int n = 14}) {
  final len = c.length;
  final out = _nan(len);
  if (len < n + 1) return out;
  var g = 0.0, l = 0.0;
  for (var i = 1; i <= n; i++) {
    final d = c[i] - c[i - 1];
    if (d > 0) {
      g += d;
    } else {
      l -= d;
    }
  }
  g /= n;
  l /= n;
  double val(double g, double l) => l == 0 ? (g == 0 ? 50 : 100) : 100 - 100 / (1 + g / l);
  out[n] = val(g, l);
  for (var i = n + 1; i < len; i++) {
    final d = c[i] - c[i - 1];
    g = (g * (n - 1) + (d > 0 ? d : 0)) / n;
    l = (l * (n - 1) + (d < 0 ? -d : 0)) / n;
    out[i] = val(g, l);
  }
  return out;
}

/// 布林帶寬 =（上軌 − 下軌）÷ 中軌（規格書 §8.2 波動壓縮）。
Float64List bbWidthSeries(List<double> c, {int n = 20, double k = 2}) {
  final mid = smaSeries(c, n);
  final out = _nan(c.length);
  for (var i = n - 1; i < c.length; i++) {
    var ss = 0.0;
    for (var j = i - n + 1; j <= i; j++) {
      final d = c[j] - mid[i];
      ss += d * d;
    }
    final sd = math.sqrt(ss / n);
    if (mid[i] != 0) out[i] = 2 * k * sd / mid[i];
  }
  return out;
}

class KdSeries {
  final Float64List k, d;
  KdSeries(this.k, this.d);
}

/// 台股常用的 KD(9,3,3)（規格書 §7.2：只作短週期輔助）。
KdSeries kdSeries(List<double> h, List<double> l, List<double> c, {int n = 9}) {
  final len = c.length;
  final k = _nan(len), d = _nan(len);
  var kv = 50.0, dv = 50.0;
  for (var i = n - 1; i < len; i++) {
    var hh = double.negativeInfinity, ll = double.infinity;
    for (var j = i - n + 1; j <= i; j++) {
      hh = math.max(hh, h[j]);
      ll = math.min(ll, l[j]);
    }
    final rsv = hh == ll ? 50.0 : (c[i] - ll) / (hh - ll) * 100;
    kv = kv * 2 / 3 + rsv / 3;
    dv = dv * 2 / 3 + kv / 3;
    k[i] = kv;
    d[i] = dv;
  }
  return KdSeries(k, d);
}

Float64List obvSeries(List<double> c, List<double> v) {
  final out = Float64List(c.length);
  for (var i = 1; i < c.length; i++) {
    out[i] = out[i - 1] + (c[i] > c[i - 1] ? v[i] : (c[i] < c[i - 1] ? -v[i] : 0));
  }
  return out;
}

/// v[from..to]（含兩端）的最大值；範圍不合法回傳 NaN。
double maxIn(List<double> v, int from, int to) {
  if (from < 0 || to >= v.length || from > to) return double.nan;
  var m = double.negativeInfinity;
  for (var i = from; i <= to; i++) {
    if (v[i] > m) m = v[i];
  }
  return m;
}

double minIn(List<double> v, int from, int to) {
  if (from < 0 || to >= v.length || from > to) return double.nan;
  var m = double.infinity;
  for (var i = from; i <= to; i++) {
    if (v[i] < m) m = v[i];
  }
  return m;
}

double avgIn(List<double> v, int from, int to) {
  if (from < 0 || to >= v.length || from > to) return double.nan;
  var s = 0.0;
  for (var i = from; i <= to; i++) {
    s += v[i];
  }
  return s / (to - from + 1);
}

/// 一檔股票所有指標的整條序列。短線分析、持股追蹤、自訂篩選共用同一份，
/// 確保各處用的是一模一樣的判斷邏輯。
class StockSeries {
  final String code;
  final List<DailyBar> bars;
  final Float64List open, high, low, close, vol, value; // value：成交值（元，估算）
  final Float64List ema20, ema50, ema100, ema200;
  final Float64List sma20, sma60, sma120, sma240;
  final Float64List atr, rsi, bbw;
  final AdxSeries adx;
  final MacdSeries macd;
  final KdSeries kd;
  final Float64List obv;

  StockSeries._(
    this.code,
    this.bars,
    this.open,
    this.high,
    this.low,
    this.close,
    this.vol,
    this.value,
    this.ema20,
    this.ema50,
    this.ema100,
    this.ema200,
    this.sma20,
    this.sma60,
    this.sma120,
    this.sma240,
    this.atr,
    this.rsi,
    this.bbw,
    this.adx,
    this.macd,
    this.kd,
    this.obv,
  );

  factory StockSeries(String code, List<DailyBar> bars) {
    final n = bars.length;
    final o = Float64List(n), h = Float64List(n), l = Float64List(n), c = Float64List(n);
    final v = Float64List(n), val = Float64List(n);
    for (var i = 0; i < n; i++) {
      final b = bars[i];
      o[i] = b.open;
      h[i] = b.high;
      l[i] = b.low;
      c[i] = b.close;
      v[i] = b.volumeLots.toDouble();
      val[i] = b.close * b.volumeLots * 1000;
    }
    return StockSeries._(
      code,
      bars,
      o,
      h,
      l,
      c,
      v,
      val,
      emaSeries(c, 20),
      emaSeries(c, 50),
      emaSeries(c, 100),
      emaSeries(c, 200),
      smaSeries(c, 20),
      smaSeries(c, 60),
      smaSeries(c, 120),
      smaSeries(c, 240),
      atrSeries(h, l, c),
      rsiSeries(c),
      bbWidthSeries(c),
      adxSeries(h, l, c),
      macdSeries(c),
      kdSeries(h, l, c),
      obvSeries(c, v),
    );
  }

  int get length => close.length;

  /// n 日報酬率（%）；資料不足回傳 NaN。
  double roc(int i, int n) => i - n < 0 || close[i - n] == 0 ? double.nan : (close[i] / close[i - n] - 1) * 100;

  /// 前 n 天（不含第 i 天）的平均成交量。
  double avgVolBefore(int i, int n) => avgIn(vol, i - n, i - 1);

  /// 前 n 天（不含第 i 天）的平均成交值。
  double avgValueBefore(int i, int n) => avgIn(value, i - n, i - 1);

  /// 「還原權息後」這天相對前一天的漲跌幅（%）。
  double changePct(int i) => i == 0 || close[i - 1] == 0 ? double.nan : (close[i] / close[i - 1] - 1) * 100;

  /// 這天是否收在漲停（以參考價 +9.5% 以上、而且收在最高價判斷；
  /// 實際漲停價要依 tick 取整，這裡用保守的近似）。
  bool isLimitUp(int i) {
    if (i == 0) return false;
    final ref = bars[i].refPrice ?? bars[i - 1].close;
    return ref > 0 && bars[i].close >= ref * 1.095 && bars[i].close >= bars[i].high;
  }

  bool isLimitDown(int i) {
    if (i == 0) return false;
    final ref = bars[i].refPrice ?? bars[i - 1].close;
    return ref > 0 && bars[i].close <= ref * 0.905 && bars[i].close <= bars[i].low;
  }

  /// 某個指標第 i 天的值在它自己過去 [window] 天裡的百分位（0～1），
  /// 例如布林帶寬處於歷史低分位（規格書 §8.2）。
  double percentileOf(Float64List s, int i, int window) {
    if (!ok(s[i])) return double.nan;
    var below = 0, count = 0;
    for (var j = math.max(0, i - window + 1); j <= i; j++) {
      if (!ok(s[j])) continue;
      count++;
      if (s[j] <= s[i]) below++;
    }
    return count < 20 ? double.nan : below / count;
  }
}
