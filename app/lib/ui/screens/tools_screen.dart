/// 「工具」：方法說明、長期資料包、每日行情資料管理。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_build_info.dart';
import '../../data/datapack_store.dart';
import '../../data/longterm_store.dart';
import '../layout.dart';
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
          '六大類因子、組合規則、市場環境、汰弱留強、回測怎麼做、資料來源',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MethodScreen())),
        ),
        tile(
          Icons.cloud_download_outlined,
          '長期資料包',
          pack.hasPack ? '資料到 ${pack.lastDate ?? '—'}，本機 ${(pack.localBytes / 1e6).toStringAsFixed(1)} MB' : '還沒下載',
          () => push('長期資料包', const DataPackScreen()),
        ),
        tile(Icons.storage_outlined, '每日行情（短線、持股、圖表用）', '回看天數、同步狀態、存放位置、清除', () => push('每日行情', const DataScreen())),
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
    Widget sec(String title, List<String> items, {BulletKind kind = BulletKind.info}) =>
        SectionCard(title: title, child: Bullets(items, kind));
    return Scaffold(
      appBar: AppBar(title: const Text('系統方法說明')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text(
                '核心原則：長期投資，持有台股最大的公司、避開有地雷的，照市值配置、每月檢視一次。'
                '不預測誰會漲最多——真實資料檢驗過，全市場評分挑贏家沒有比較好；評分只用來「排除地雷」。'
                '規則事先決定、用沒看過的期間檢驗，不拿回測結果去調。',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 8),
              sec('大型股避雷組合', [
                '範圍：上市公司市值（證交所公布的發行股數 × 股價）前 30 大。每月檢視日用當天的股數和收盤價。',
                '地雷：虧損、年線下彎又營收衰退、殖利率陷阱（配的比賺的多）、成交量太小、總分在全市場後 20%。有其中一項就不買，手上有的建議換掉。',
                '比重：沒地雷的照市值；單一檔最多 40%（連 0050 裡的一起算，台積電通常會碰到上限）。',
                '不到 1.5% 的小部位改放 0050（006208 也可以），不買零碎部位。',
                '每月 11 日以後第一個交易日檢視、隔天收盤調整；比重跟目標差不到 1/4 就不調，減少交易。',
              ]),
              sec('為什麼這樣做（檢驗過程）', [
                '舊方法「全市場評分、挑分數最高的 15 檔」：每個月的名單抱 3～6 個月，贏大盤的次數大約一半；挑到的多是冷門中小型股，比例零碎、不好買。',
                '原因：分數很會找出「最差的」股票（之後明顯落後），但挑不出「最好的」；各類分數的效果也會隨年代改變。',
                '台股動能效果很弱、甚至會反轉（學術研究一致）；價值、低波動、品質比較有證據，但主要用處是避開爛股。',
                '所以改成「照市值持有大型股、只去掉地雷」。規則只用 2014–2019 年決定，2020 以後是事先沒看過的檢驗：兩段都比單純持有大型股好一點，也比大盤（含息）好。',
                '代價：大型股、尤其台積電佔很重，最大跌幅比整個大盤深。單一檔 40% 的上限是為了降低這個風險（不設上限報酬高一點，但台積電會超過六成）。',
                '不想管個股的話，全部買 0050 長期抱著，結果也差不多（每年少一點點）。',
              ], kind: BulletKind.warn),
              sec('評分（用來判斷地雷）', [
                '六大類：動能趨勢、營收成長、獲利品質、價值股利各 20%，法人籌碼、穩定度各 10%，換成全市場百分位再加權。',
                '短期過熱：一個月漲超過 30% 或股價高出年線 30%——組合照比重分批買就好，不用追。',
                '年線下彎：股價在年線下、年線也往下。營收衰退：近 3 個月年減 10% 以上且一年中多數月份衰退。',
                '殖利率陷阱：配的比賺的多（配息率 > 100%），或殖利率很高但獲利大減。',
                '個股報告、比較頁都看得到每一檔的分數和地雷。',
              ]),
              sec('依我的持股調整', [
                '在組合裡的：續抱，顯示目標比重；比目標高很多的，新錢先買其他檔。',
                '有地雷的：建議換掉，換成組合裡還沒持有、比重大的公司；一個月最多換你設定的檔數（2～5），最弱的先換。',
                '不在前 30 大但沒有地雷的：不急著換，可以續抱，之後慢慢換成組合裡的股票。',
                '0050、006208 算組合裡的 0050；比例跟建議差超過 10 個百分點才提醒，用新資金慢慢調。',
              ]),
              sec('回測（不偷看未來）', [
                '每月只用當時看得到的資料：當天公布的發行股數和收盤價、當時的評分（營收假設 11 日以後才知道）。',
                '扣成本：買進手續費 0.1425% ＋ 滑價 0.1%，賣出再加證交稅 0.3%；配息再投入（總報酬）。',
                '減資、變更面額（例如股票分割）照證交所公布的恢復買賣參考價接起來，不會被當成暴漲暴跌。',
                '比較對象：0050（用市值前 50 大每月調整模擬）、加權股價報酬指數（含息）。',
                '另外列出：逐年、大跌期間、地雷成績單（被排除的之後表現）、舊方法的成績、各類分數的因子研究。',
              ]),
              sec('市場環境（參考）', [
                '台股：加權指數在不在年線上、年線方向、站上年線的股票比例；國際：費城半導體、Nasdaq、VIX、台幣、美債殖利率。',
                '只當參考，組合本身不因為環境擇時進出（擇時通常弊多於利）。',
              ]),
              sec('持股（長期模式）', [
                '長期持有：看年線和「從持有期間高點回落多少」（預設 25%）提醒減碼，不用短線停損。',
                '每檔持股顯示長期總分與旗標；排名掉到後段或理由破壞會列在「需要注意」。',
                '股利：依證交所除權息資料（上櫃用參考價推算）估算持有期間領到的現金股利。',
                'stock_acc 同步：只讀不寫，資料不離開這台電腦；沒有 stock_acc 的電腦整組隱藏。',
              ]),
              sec('短線（最右邊的「短線」分頁）', [
                'A 突破、B 回檔、C 趨勢延續、D 超跌反彈四種進場訊號，搭配市場、產業、相對強度的一票否決與交易計畫。',
                '短線規則用過去資料回測扣成本後並沒有穩定賺錢，所以只留著參考：給喜歡短線的朋友，或挑長期股票的進場時機（避開過熱）。',
                '今日雷達（盤中即時報價）、自訂條件篩選也在那裡。',
              ]),
              sec('限制', [
                '資料從 2013 年開始（月營收改合併報表之後）；回測從 2014 年起，約 12 年，涵蓋 2015、2018、2020、2022 幾次大跌。',
                '財報只用本益比、淨值比推算的 ROE、EPS（近四季），沒有現金流、負債比等細項。',
                '過去的成績不代表未來；這是依公開資料與固定規則算出的參考，不是投資建議。',
              ], kind: BulletKind.warn),
            ],
          ),
        ),
      ),
    );
  }
}
