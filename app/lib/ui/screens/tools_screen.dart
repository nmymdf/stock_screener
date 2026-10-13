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
          '名單規則、持股健檢、檢驗方式、沒採用的方法、免責聲明',
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
                ('選股頁', '兩份候選名單（強勢成長、穩健存股）由你挑，不給比例；手上的持股逐檔健檢。'),
                ('先說實話', '過去 12 年，一檔上市股票抱一年贏 0050 的機會只有三成多。名單的用處是幫你挑、幫你避雷，不是保證贏 0050。'),
                ('怎麼來的', '用 2014–2026 的真實資料檢驗了二十幾種方法（含國外有名的）；規則先定好再檢驗，沒用的不放進來。'),
              ]),
              sec('強勢成長名單', [
                ('多頭排列', '股價 > 50 日線 > 150 日線 > 200 日線，200 日線還在往上。'),
                ('接近高點', '離一年高點 25% 以內，而且比一年低點高 30% 以上。'),
                ('相對強度', '一年漲幅在全市場前 30%；照一年漲幅排，最多 10 檔，同一產業最多 2 檔。'),
                ('營收', '近 3 個月營收年增 20% 以上（只追有業績撐的強勢股）。'),
                ('買得到', '每天平均成交 2 億元以上；沒有地雷（虧損、年線下彎又營收衰退、殖利率陷阱）。'),
                ('出場', '收盤跌破 50 日均線就走。'),
                ('成績', '抱 3～6 個月：多頭年（2020 以後）賺錢機率約七成、平均比 0050 多；盤整年輸 0050。抱一年大多輸 0050。'),
                ('根據', 'Minervini 的趨勢模板、O\'Neil 的 CAN SLIM，加上台股的月營收。'),
              ]),
              sec('穩健存股名單', [
                ('規模', '上市公司市值前 100 大。'),
                ('配息', '近 5 年每年都配息，殖利率 3% 以上；照殖利率排，最多 10 檔，同一產業最多 2 檔。'),
                ('穩定', '一年波動低於這群大公司的中位數，年線沒有下彎，沒有地雷。'),
                ('成績', '報酬比 0050 少；但抱一年賺錢的機率約 84%，最差一次只跌約 13%。'),
              ]),
              sec('持股健檢', [
                ('趨勢正常', '站在年線上、長期理由還在：可以續抱。'),
                ('跌破年線', '股價在 200 日均線之下：之後幾個月通常比較弱。'),
                ('理由破壞', '趨勢轉弱又營收衰退、虧損又轉弱，或總分掉到全市場後 15%：建議檢討。'),
                ('六個面向', '趨勢、營收、獲利、價格、法人、波動，各給好／中／差（全市場前 1/3、中間、後 1/3），附實際數字。'),
                ('成績', '之後 6 個月平均：2014–2019 趨勢正常 +3.6%、跌破年線 +1.1%、理由破壞 0.0%；2020 以後 +14.5%、+5.4%、+8.8%。看一年就差不多。'),
                ('上櫃、ETF', '沒有評分：0050 類看大盤在不在年線上；其他看自己的價格在不在年線上。'),
              ]),
              sec('大盤狀態（0050 的抱法）', [
                ('規則', '大盤（加權報酬指數）在 200 日均線上就抱 0050，跌破就先減碼，等站回去再買；每月看一次。'),
                ('成績', '2014 年以來報酬跟一直抱差不多，最大跌幅少三分之一以上（20% 對 32%）。'),
                ('根據', 'Faber 的 10 個月均線擇時。'),
              ]),
              sec('檢驗方式', [
                ('不偷看未來', '每月只用當時看得到的股價、營收、評分；名單包含之後下市的股票。'),
                ('扣成本', '買進手續費 0.1425% ＋ 滑價 0.1%，賣出再加證交稅 0.3%；配息再投入，減資和股票分割照證交所參考價。'),
                ('兩段期間', '2014–2019（多半盤整）、2020 以後（強勢多頭）分開看。'),
              ]),
              sec('沒採用的方法', [
                ('剛轉強', '剛站上年線、營收加速：抱一年贏 0050 只有 37%。'),
                ('相對便宜', '本益比在自己 5 年低檔：抱一年贏 0050 只有 20%。'),
                ('配比例的策略', '穩健 70%＋強勢 30%：數字好看，但要每天照規則買賣；改成名單由你挑。'),
                ('全市場評分', '每月名單贏大盤的次數約一半，挑到冷門股。'),
                ('市值加權去地雷', '幾乎就是 0050（放在「市值」頁當排行參考）。'),
                ('神奇公式、趨勢價值、低波動、產業動能', '在台股成交量大的股票裡，近年都沒有贏平均股票。'),
              ]),
              sec('其他分頁', [
                ('市值', '上市公司市值排行，附收盤、一年走勢、量和地雷標記；只是排行，不是推薦。'),
                ('持股', '手動／模擬、stock_acc 記帳兩組；stock_acc 只讀不寫，資料不離開這台電腦，沒有 stock_acc 的電腦整組隱藏。'),
                ('比較、產業、市場', '看懂一檔股票、同業比較、市場環境（參考）。'),
                ('短線', 'A／B／C／D 短線訊號、今日雷達、自訂篩選。短線規則回測扣成本後沒有穩定賺錢，只留著參考。'),
              ]),
              sec('限制', [
                ('資料', '2013 年起；長歷史只有上市股票、只有收盤價；沒有完整財報（現金流、負債）。'),
                ('運氣', '規則先定好再檢驗，但試過很多方法，多少有運氣成分；未來大概會比回測差一些。'),
              ]),
              SectionCard(title: '免責聲明', child: InfoTable(kDisclaimerFull, keyWidth: 120)),
            ],
          ),
        ),
      ),
    );
  }
}
