/// 「工具」：方法說明、長期資料包、每日行情資料管理。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_build_info.dart';
import '../../data/datapack_store.dart';
import '../../data/longterm_store.dart';
import '../layout.dart';
import '../widgets/common.dart';
import '../widgets/score_widgets.dart';
import 'data_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void push(String title, Widget body) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280), child: body),
          ),
        ),
      ),
    );
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap) => Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
    final pack = context.watch<DataPackStore>();
    return ListView(
      padding: pagePadding(context),
      children: [
        const PageHeader(icon: Icons.build, title: '工具', subtitle: '方法說明、長期資料包、每日行情'),
        tile(
          Icons.menu_book_outlined,
          '系統方法說明',
          '策略規則、檢驗方式、沒採用的方法、限制、免責聲明',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MethodScreen())),
        ),
        tile(
          Icons.cloud_download_outlined,
          '長期資料包',
          pack.hasPack ? '資料到 ${pack.lastDate ?? '—'}，本機 ${(pack.localBytes / 1e6).toStringAsFixed(1)} MB' : '還沒下載',
          () => push('長期資料包', const DataPackScreen()),
        ),
        tile(Icons.storage_outlined, '每日行情（短線、持股、圖表用）', '回看天數、同步狀態、存放位置、清除', () => push('每日行情', const DataScreen())),
        tile(Icons.gavel_outlined, '免責聲明', kDisclaimerShort, () => showDisclaimerDialog(context, requireAccept: false)),
        const SizedBox(height: 16),
        Center(child: Text('台股選股 $kAppVersion', style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

class DataPackScreen extends StatelessWidget {
  const DataPackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = context.watch<DataPackStore>();
    final lt = context.read<LongTermStore>();
    final files = pack.local.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SectionCard(
          title: '狀態',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KvRow('資料到', pack.lastDate ?? '—'),
              KvRow('上次檢查', pack.lastCheck == null ? '—' : pack.lastCheck!.toLocal().toString().substring(0, 16)),
              KvRow('本機大小', '${(pack.localBytes / 1e6).toStringAsFixed(1)} MB（${files.length} 個檔案）'),
              const SizedBox(height: 8),
              if (pack.updating) ...[
                LinearProgressIndicator(value: pack.totalBytes > 0 ? pack.doneBytes / pack.totalBytes : null),
                const SizedBox(height: 4),
                Text(
                  pack.totalBytes > 0
                      ? '下載中… ${(pack.doneBytes / 1e6).toStringAsFixed(1)} / ${(pack.totalBytes / 1e6).toStringAsFixed(1)} MB'
                      : '檢查中…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: lt.updatePack,
                      icon: const Icon(Icons.sync, size: 18),
                      label: Text(pack.hasPack ? '檢查更新' : '下載長期資料（約 30 MB）'),
                    ),
                    if (pack.hasPack)
                      OutlinedButton.icon(
                        onPressed: () => _confirmClear(context, pack),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('刪除本機資料包'),
                      ),
                  ],
                ),
              if (pack.error != null) ...[
                const SizedBox(height: 6),
                Text(pack.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
              ],
            ],
          ),
        ),
        const SectionCard(
          title: '資料從哪裡來',
          child: Bullets([
            'GitHub Actions 每個交易日台北時間 21:30 左右自動抓、整理、打包，放在本專案的 GitHub Releases「data」。',
            '證交所：每日收盤行情與加權指數、發行量加權股價報酬指數（含息）、本益比／股價淨值比／殖利率、三大法人買賣超、除權息。',
            '公開資訊觀測站：上市公司每月營收（同時記錄當時報表的去年同月營收）。',
            'Yahoo Finance：費城半導體、Nasdaq、VIX、美元兌台幣、美國 10 年期公債殖利率。',
            'App 打開時會檢查更新，之後每小時一次；今天 15:00 以後的收盤仍然直接跟證交所抓，不用等晚上的資料包。',
            '只有下載、不會上傳任何東西；持股和 stock_acc 的資料只留在這台電腦。',
          ], BulletKind.info),
        ),
        if (files.isNotEmpty)
          SectionCard(
            title: '本機檔案',
            child: Column(
              children: [
                for (final f in files)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.name, style: const TextStyle(fontSize: 13)),
                              if (f.first != null || f.last != null)
                                Text(
                                  '${f.first ?? ''}${f.last == null ? '' : '～${f.last}'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Text('${(f.size / 1e6).toStringAsFixed(2)} MB', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                if (pack.dirPath != null) ...[
                  const Divider(),
                  SelectableText(pack.dirPath!, style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, DataPackStore pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除本機資料包？'),
        content: const Text('長期分析的資料會被刪掉，之後要重新下載（約 30 MB）。持股紀錄不受影響。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok == true) await pack.clear();
  }
}

class MethodScreen extends StatelessWidget {
  const MethodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget sec(String title, List<(String, String)> rows, {double keyWidth = 120}) => SectionCard(
      title: title,
      child: InfoTable(rows, keyWidth: keyWidth),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('系統方法說明')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              sec('一句話', [
                ('策略', '穩健 70%（0050＋大盤 200 日均線）＋進攻 30%（強勢股＋50 日均線停損）；每月檢視一次，每天看停損。'),
                ('目標', '長期比 0050 多賺一點、大跌少很多。不是聖杯：盤整年大約跟 0050 打平。'),
                ('怎麼來的', '用 2014–2026 的真實資料檢驗了二十幾種方法（含國外有名的），這是唯一經得起檢查的組合。'),
              ]),
              sec('穩健 70%：0050＋大盤均線', [
                ('持有', '大盤（加權報酬指數）在 200 日均線上就持有 0050（006208 也可以）。'),
                ('現金', '跌破 200 日均線就賣出，改放現金，等站回去再買。'),
                ('檢視', '每月 11 日以後第一個交易日收盤後看一次，隔天收盤調整；12 年大約進出 14 次。'),
                ('根據', 'Faber 的 10 個月均線擇時；台股回測：報酬跟一直持有差不多，最大跌幅少三分之一（2022 年 -5% 對 -22%）。'),
              ]),
              sec('進攻 30%：強勢股＋停損', [
                ('多頭排列', '股價 > 50 日線 > 150 日線 > 200 日線，200 日線還在往上。'),
                ('接近高點', '離一年高點 25% 以內，而且比一年低點高 30% 以上。'),
                ('相對強度', '一年漲幅在全市場前 30%；最後取最強的 10 檔，每檔 3%。'),
                ('營收', '近 3 個月營收年增 20% 以上（只追有業績撐的強勢股）。'),
                ('買得到', '每天平均成交 2 億元以上；沒有地雷（虧損、年線下彎又營收衰退、殖利率陷阱）。'),
                ('停損', '任何一檔收盤跌破 50 日均線，當天賣出放現金，下次檢視再重新挑。'),
                ('根據', 'Minervini 的趨勢模板、O\'Neil 的 CAN SLIM。不足 10 檔的部分放 0050。'),
              ]),
              sec('檢驗方式', [
                ('不偷看未來', '每月只用當時看得到的股價、營收、評分；名單包含之後下市的股票。'),
                ('扣成本', '買進手續費 0.1425% ＋ 滑價 0.1%，賣出再加證交稅 0.3%；配息再投入，減資和股票分割照證交所參考價。'),
                ('兩段期間', '2014–2019（多半盤整）、2020 以後（強勢多頭）分開看。'),
                ('穩健性', '挑 5～15 檔、相對強度和營收門檻、進攻比例 20～40% 都試過：每一種都比 0050 跌得少、2020 以後都多賺；2014–2019 好壞各半。'),
              ]),
              sec('沒採用的方法', [
                ('全市場評分', '每月名單贏大盤的次數約一半，挑到冷門股。'),
                ('市值加權去地雷', '幾乎就是 0050（放在「市值」頁當排行參考）。'),
                ('神奇公式、趨勢價值、低波動', '在台股成交量大的股票裡，近年都沒有贏平均股票。'),
                ('產業動能', '輸 0050。'),
                ('自訂長／中／短期規則', '高股息存股、成長＋品質、營收公告後延續：都沒有穩定贏平均股票。'),
              ]),
              sec('依我的持股調整', [
                ('0050 類', '跟著大盤 200 日均線：在線上續抱，跌破改放現金。'),
                ('名單裡的', '還在 50 日均線上就續抱；跌破就賣。'),
                ('名單外的', '跌破 50 日均線建議賣出；還在均線上可以續抱，新的錢買名單裡的。'),
              ]),
              sec('其他分頁', [
                ('市值', '上市公司市值排行，附收盤、一年走勢、量和地雷標記；只是排行，不是推薦。'),
                ('持股', '手動／模擬、stock_acc 記帳兩組；stock_acc 只讀不寫，資料不離開這台電腦，沒有 stock_acc 的電腦整組隱藏。'),
                ('比較、產業、市場', '看懂一檔股票、同業比較、市場環境（參考）。'),
                ('短線', 'A／B／C／D 短線訊號、今日雷達、自訂篩選。短線規則回測扣成本後沒有穩定賺錢，只留著參考。'),
              ]),
              sec('限制', [
                ('資料', '2013 年起；長歷史只有上市股票、只有收盤價（停損用收盤判斷）；沒有完整財報（現金流、負債）。'),
                ('運氣', '試了很多方法後挑出最好的，多少有運氣成分；未來大概會比回測差一些。'),
              ]),
              SectionCard(title: '免責聲明', child: InfoTable(kDisclaimerFull, keyWidth: 120)),
            ],
          ),
        ),
      ),
    );
  }
}
