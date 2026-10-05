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
                '核心原則：長期投資（持有 1～6 個月以上），找「穩定成長、體質好、價格合理、有人在買」的上市公司，'
                '分散成 10～15 檔，每月檢視一次、汰弱留強。不一大漲就追、不一下跌就賣；規則事先決定，不拿回測結果去調。',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 8),
              sec('選股範圍', [
                '上市普通股（四位數代號、不含 ETF、特別股、存託憑證），包含之後下市的股票（回測沒有存活者偏差）。',
                '新買進還要：近 60 個交易日平均每天成交 5,000 萬元以上、股價 10 元以上、上市滿一年。',
                '上櫃、ETF 不做長期評分（流動性與資訊揭露差異大）；持股裡有的會標「不在評分範圍」。',
              ]),
              sec('六大類分數（每月檢視日計算，全市場百分位）', [
                '動能趨勢 20%：近 12 個月（扣掉最近 1 個月）與近 6 個月的含息報酬、站上年線的程度（超過 30% 不再加分）、年線方向。',
                '營收成長 20%：近 3 個月營收年增率、近 12 個月有幾個月成長、近 12 個月累計年增、成長加速。年增率一律用同一份月報的「去年同月營收」算。',
                '獲利品質 20%：ROE（＝股價淨值比 ÷ 本益比，近四季）的高低與近 3 年穩定度、每股盈餘一年來的成長；虧損排最後。',
                '價值股利 20%：本益比在自己過去 5 年的位置、盈餘殖利率、現金殖利率（殖利率陷阱不加分）、近 5 年配息年數。',
                '法人籌碼 10%：外資、投信近 60 個交易日買賣超佔成交量的比例。',
                '穩定度 10%：近一年波動度、一年內最大跌幅（越小越好）。',
                '總分＝有資料的類別依權重加權；短期過熱扣 8 分、虧損扣 5 分。',
              ]),
              sec('警示旗標與「長期理由破壞」', [
                '短期過熱：一個月漲超過 30% 或股價高出年線 30%——不追高，等回穩。',
                '年線下彎：股價在年線下、年線也往下。營收衰退：近 3 個月年減 10% 以上且一年中多數月份衰退。',
                '殖利率陷阱：配的比賺的多（配息率 > 100%），或殖利率很高但獲利大減。',
                '長期理由破壞＝年線下彎＋營收衰退、虧損＋年線下彎、或總分掉到全市場後 15%：不受「至少抱 3 個月」限制，建議換掉。',
              ], kind: BulletKind.warn),
              sec('理想組合規則', [
                '每月 11 日以後第一個交易日收盤後檢視（月營收 10 日前公布完），隔天收盤調整。',
                '新買：總分前 10%、沒有過熱、沒有虧損、長期理由成立。續抱：還在前 30% 就不動。',
                '至少抱 3 個月（約 63 個交易日），除非長期理由破壞。每月最多換 5 檔（可改 2～5），換上去的要比換下來的百分位高 20 以上。',
                '權重：分數 ÷ 波動度，分數高、波動低的配越多；單一檔最多 15%（漲到 20% 以上調回 15%）、單一產業最多 30%。',
                '「組合」頁的理想組合，就是同一套規則從 2014 年一路操作到今天的實際持股，所以回測成績就是它過去的成績。',
              ]),
              sec('大盤核心（可選）', [
                '台股加權指數由少數大型股（尤其台積電）主導，分散的選股組合在大型股領漲的年份很難跟上指數。',
                '可以把 30% 或 50% 放在市值型 ETF（0050／006208），其餘才選股；每月檢視時調回比例。',
                '回測頁的「不同設定比較」列出全部選股、核心 30%、核心 50% 三種結果，自己決定要哪一種。',
              ]),
              sec('市場環境（建議股票比例）', [
                '台股：加權指數在不在年線上、年線方向、站上年線的股票比例 → 積極 100%／中性 75%／保守 50%。',
                '國際（可選）：費城半導體跌破年線且年線下彎、Nasdaq 跌破年線、VIX 十日平均 > 25、台幣三個月貶值 > 3%、美債殖利率半年上升 > 0.75 個百分點；五項中三項以上就再降一級。',
                '國際資料只用台股前一天以前的美國收盤（美國收盤在台灣開盤之前），只調整股票比例、不用來挑股票。',
                '只在每月檢視日調整，按比例減碼、不換股；單日大跌不會叫你賣。回測頁可以比較「一直滿倉」「看台股」「台股＋國際」三種。',
              ]),
              sec('依我的持股汰弱留強', [
                '續抱：長期理由還在、排名在前段。觀察：排名中後段、或有年線下彎／營收衰退／獲利大減，或持有未滿 3 個月。',
                '建議汰換：長期理由破壞，或排名後 30% 又抱超過 3 個月。最弱的先換，一個月最多換你設定的檔數（2～5）。',
                '替代股：總分前 15%、比被換掉的百分位高 25 以上、不過熱、不虧損、換了之後產業不超過 30%。',
                '另外提醒：單一檔超過 15%、單一產業超過 30%、檔數太少。',
              ]),
              sec('回測與因子研究（不偷看未來）', [
                '本益比、殖利率用當天公布的值；月營收保守假設每月 11 日以後才知道上個月的；股價只用當天以前的；除權息照實際參考價。',
                '扣成本：買進手續費 0.1425% ＋ 滑價 0.1%，賣出再加證交稅 0.3%；配息再投入（總報酬）。',
                '比較基準：加權股價報酬指數（含息），以及「全部可投資股票平均分配」。',
                '另外列出：逐年、每月贏指數比例、每筆持股賺錢比例、週轉率、前後半段、大跌期間、不同設定比較。',
                '因子研究：每月依分數分五組，看之後 3 個月的超額報酬與資訊係數（IC），檢查每類分數是不是真的有用。',
                '最新一天（現在）的評分則用手上所有已公布的資料（例如當月 5 日公布的營收）。',
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
