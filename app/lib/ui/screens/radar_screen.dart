/// 「今日雷達」（沿用 stock_acc 的選股雷達）：抓候選股當天的即時報價，用
/// 今日漲幅、量能、股價貼近今日高點排名，附上每一檔的理由。
/// 機械化排序，不是投資建議。
library;

import 'package:flutter/material.dart';

import '../../data/stock_catalog.dart';
import '../../logic/momentum.dart';
import '../../services/quote_service.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'stock_report_screen.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final _service = QuoteService();
  bool _loading = false;
  bool _fullMarket = false;
  List<MomentumHit>? _hits;
  String? _error;
  int _scanned = 0;
  int _total = 0;
  int _fetchedCount = 0;

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
      _hits = null;
      _scanned = 0;
      _fetchedCount = 0;
    });
    try {
      final candidates = {...kScreenerCandidateCodes, if (_fullMarket) ...kBuiltinStocksByCode.keys}.toList();
      setState(() => _total = candidates.length);

      final quotes = <LiveQuote>[];
      const batch = QuoteService.batchSize;
      const chunk = batch * 4; // 每次同時發出 4 批請求，加快全市場掃描
      for (var i = 0; i < candidates.length; i += chunk) {
        final part = candidates.sublist(i, i + chunk > candidates.length ? candidates.length : i + chunk);
        final sub = <List<String>>[
          for (var j = 0; j < part.length; j += batch)
            part.sublist(j, j + batch > part.length ? part.length : j + batch),
        ];
        final results = await Future.wait(sub.map(_service.fetch));
        for (final r in results) {
          quotes.addAll(r);
        }
        if (mounted) setState(() => _scanned = (i + chunk).clamp(0, candidates.length));
      }

      final hits = rankByMomentum(quotes);
      if (mounted) {
        setState(() {
          _hits = hits;
          _fetchedCount = quotes.length;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '掃描失敗，請確認有網路連線後再試一次');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const DisclaimerCard(
          text:
              '這是機械化的排名（今天的漲跌幅、量能、股價位置），不是投資建議、'
              '也不是預測——沒有人能保證這些股票之後會賺錢，買賣前務必自己再確認。',
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('全市場掃描', style: TextStyle(fontSize: 13)),
          subtitle: Text(
            _fullMarket ? '掃全部上市櫃股票（約 2300 檔，較慢）' : '只掃熱門股/ETF 候選池（約 180 檔，較快）',
            style: const TextStyle(fontSize: 11),
          ),
          value: _fullMarket,
          onChanged: _loading ? null : (v) => setState(() => _fullMarket = v),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _run,
            icon: _loading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar, size: 18),
            label: Text(_loading ? '掃描中… $_scanned / $_total' : '開始掃描'),
          ),
        ),
        const SizedBox(height: 10),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (_hits != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '成功取得 $_fetchedCount / $_total 檔候選的報價',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          SectionHeader(left: '今日動能排行（共 ${_hits!.length} 檔上漲候選）', right: _hits!.isEmpty ? null : '前 5 名特別標記'),
          RowList(
            emptyText: _fetchedCount == 0
                ? '沒有抓到任何報價——可能是非交易時段、或網路連不到證交所，晚點/開盤時間再試一次'
                : '這次掃描沒有符合條件（今天上漲）的候選股，可能是非交易時段（報價都是昨收）或今天普遍下跌',
            children: [for (var i = 0; i < _hits!.length; i++) _HitRow(rank: i + 1, hit: _hits![i])],
          ),
        ],
      ],
    );
  }
}

class _HitRow extends StatelessWidget {
  final int rank;
  final MomentumHit hit;
  const _HitRow({required this.rank, required this.hit});

  @override
  Widget build(BuildContext context) {
    final name = kBuiltinStocksByCode[hit.code]?.name ?? '';
    return InfoRow(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StockReportScreen(code: hit.code, extraReasons: hit.reasons, extraTitle: '今日雷達上榜理由'),
        ),
      ),
      title: Row(
        children: [
          if (rank <= 5) RankBadge(rank: rank),
          Flexible(child: Text('${hit.code} $name', overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text(hit.reasons.join(' · ')),
      trailingTop: Text(f2(hit.quote.price)),
      trailingBottom: Text(
        pctTxt(hit.quote.changePct),
        style: TextStyle(color: changeColor(context, hit.quote.changePct)),
      ),
    );
  }
}
