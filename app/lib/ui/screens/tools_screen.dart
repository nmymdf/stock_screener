/// 「工具」：自訂條件篩選、今日即時雷達、資料管理、方法說明。
library;

import 'package:flutter/material.dart';

import '../../app_build_info.dart';
import '../widgets/score_widgets.dart';
import 'data_screen.dart';
import 'radar_screen.dart';
import 'technical_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void push(String title, Widget body) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: body),
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
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text('工具', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        tile(
          Icons.menu_book_outlined,
          '系統方法說明',
          '每個引擎怎麼算、對應規格書哪一章、還沒做的部分',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MethodScreen())),
        ),
        tile(
          Icons.filter_alt_outlined,
          '自訂條件篩選',
          '自己勾均線、RSI、量比、新高等條件篩全市場',
          () => push('自訂條件篩選', const TechnicalScreen()),
        ),
        tile(Icons.radar, '今日即時雷達', '盤中用即時報價排出今天動能最強的股票（stock_acc 的選股雷達）', () => push('今日即時雷達', const RadarScreen())),
        tile(Icons.storage_outlined, '資料管理', '歷史資料同步、回看天數、存放位置、清除', () => push('資料管理', const DataScreen())),
        const SizedBox(height: 16),
        Center(child: Text('台股選股 $kAppVersion', style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
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
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text(
                '核心原則（規格書 §1）：系統不是預測「明天一定漲哪一檔」，而是找出在目前市場環境下條件較有利的股票，'
                '並把每次判斷錯誤的損失限制在可控範圍內。市場先於個股、產業先於個股、風險管理先於報酬。',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 8),
              sec('資料', [
                '每個交易日抓一次證交所（上市）＋櫃買中心（上櫃）全市場收盤行情，存在本機；包含當天所有股票（含之後下市的），回測沒有存活者偏差。',
                '除權息還原：用交易所公布的漲跌價差推回參考價，偵測除權息日，把之前的價格等比例還原（§14）。',
                '產業別來自證交所／櫃買的官方分類（34 個產業）。',
              ]),
              sec('市場環境引擎（§2）', [
                '大盤多週期趨勢（25%）：指數對 20／60／240 日線的位置與斜率，近似日線、週線、月線。',
                '市場廣度（55%）：站上 20／60／120／240 日線的股票比例、10 日上漲下跌家數、20 日新高新低家數。',
                '恐慌指標（10%）：5 日漲停與跌停家數。',
                '指數在月線上、但站上月線的股票不到 40% → 扣分並提醒「漲勢集中在少數股票」。',
                '分成五種狀態，決定建議曝險和個股推薦門檻；空頭時停止一般多單。',
              ]),
              sec('產業輪動引擎（§3）', [
                '成員股 20／60／120 日報酬中位數、站上 20／60 日線比例、創 60 日新高比例、成交值變化，跟其他產業比排名 → 0～100 分。',
                '跟 10 個交易日前的分數比，分成領先、改善、同步、轉弱、落後。',
              ]),
              sec('個股評分（§7、§8、§10）', [
                '趨勢 15%：EMA20／50／100／200、多頭排列、EMA50 斜率、ADX+DI、MACD。',
                '相對強度 10%：20／60／120／250 日報酬加權後的全市場排名。',
                '動能 10%：RSI 用順勢解讀（50～75 最健康，不採用「低於 30 必買」）、ROC、MACD 柱、KD（只作輔助）。',
                '量價 10%：上漲日量 vs 下跌日量、OBV、價漲量增、回檔量縮。',
                '突破 5%：20／60／250 日新高、離 52 週高點距離。',
                '波動／型態 5%：布林帶寬低分位、ATR% 下降、NR7、Inside Bar（型態只加分）。',
                '市場 10%、產業 10%。',
                '總分＝有資料的模組依權重加權平均；基本面 15%、籌碼 10% 還沒接資料，暫不列入。',
              ]),
              sec('進場訊號（§9）', [
                'A 突破型：20 日窄幅整理（振幅 ≤ 25%）後，收盤突破 20 日高點、量 ≥ 1.5 倍、在 50／200 日線之上；RS 前 30%。',
                'B 回檔型：強勢股（近期創 60 日新高）回檔 ≥ 1.5 ATR 碰到 20／50 日線、量縮、RSI 回落到 35～52 後站回 50、收盤過昨高；RS 前 30%。',
                'C 趨勢延續型：前段已漲 ≥ 20%、10 天平台整理守在 50 日線上，放量突破平台；RS 前 20%。',
                'D 均值回歸型：只在震盪盤；超跌（RSI ≤ 32 或跌破布林下軌）後停止破底、收紅過昨高，目標回到 20 日線。',
              ]),
              sec('一票否決（§10.2）', [
                '流動性不足：20 日平均成交值 < 3,000 萬或均量 < 300 張。',
                '市場空頭／極端風險。',
                '歷史資料不足 60 天。',
                '合理停損過寬（> 3 ATR 或 > 10%）。',
                '報酬風險比不足（到目標或上方前高 < 2R；均值回歸 < 1.5R）。',
                '總分未達目前市場狀態的門檻；RS、趨勢分數未達策略要求。',
              ]),
              sec('交易計畫與風控（§11、§12、§14）', [
                '停損：結構停損（突破點、回檔低點、平台低點），不到 1 ATR 會放寬到 1 ATR；所有價格對齊台股跳動單位。',
                '目標 2R 先出一半；+1R 後停損拉到成本；之後用「22 日最高 − 3 ATR」移動停利；10 天沒有 +1R 就出場。',
                '不提供建議股數：每個人資金不同，畫面只給每股風險（1R）、停損距離、報酬風險比。',
                '加碼時機（只加贏家）：+1R 停損拉到成本之後第一次（≤ 原始一半），回檔不破 20 日線再轉強或整理後再突破第二次（≤ 四分之一）；虧損中禁止加碼。',
                '可接受最高買價＝收盤 + 0.5 ATR，隔天開盤超過就不追。收漲停的股票會提醒可能買不到。',
              ]),
              sec('短中長交叉分析（最終版 §02）', [
                '短期（3～10 交易日）：動能、量價狀態、20 日相對強度、位置、離 20 日線的乖離。',
                '中期（2～8 週）：日線趨勢、60／120 日相對強度、產業動能、資金累積（價量持續性）、市場。',
                '長期（技術面）：年線位置與方向、長期均線排列、一年相對強度、離高點距離、一年最大回檔、波動穩定度；要 200 天以上資料。',
                '三個分數各有自己的失效條件。依三者強弱分成：三週期共振、波段機會、長線股短線轉強、純短線戰術、中長期佳等進場點、好股票時機未到、題材波段、證據不足、三週期都弱。',
                '觀察池：中長期條件好但今天沒有進場訊號的股票，列出「什麼情況會變成可以買」（突破價、回檔區）。',
              ]),
              sec('持有期間 D1～D3 與信心度（最終版 §03）', [
                '證據來源依規格書權重：產業週期 18%、中長期趨勢 12%、相對強弱持續性 10%、價量持續性 10%、市場 8%；公司品質 22%、獲利動能 15%、事件 5% 還沒有資料，不列入。',
                'D3（2～6 個月）要長期、中期、趨勢持續性、多期間相對強度都強；D2（2～8 週）要中期分數與趨勢；D1（3～10 天）主要靠訊號和短線。',
                '市場弱勢、均值回歸、產業轉弱、信心度低、下跌放量都會往下調一級或以上，並寫出原因。',
                '信心度：多組獨立證據同向且資料滿一年是高；有 1 組矛盾是中；靠單一訊號或證據矛盾是低。',
                '每一檔都寫出「為什麼是這個期間、為什麼還不是更長、升級條件、降級條件、理由失效條件」。沒有基本面前，上限是 D3。',
              ]),
              sec('價量持續性（最終版 §04）', [
                '五種狀態：健康上升、突破確認、爆量不漲、下跌放量、縮量整理。',
                '價量持續性：60 天上漲日量 ÷ 下跌日量、OBV 方向、下跌放量的天數。',
                '突破品質：突破級別（20／60／120／250 日新高）、量能倍數、收盤位置、後續有沒有守住、乖離、大盤與產業是否同步。',
              ]),
              sec('歷史勝率與典型走勢', [
                '用本機所有資料、跟推薦完全相同的條件，把過去每一次訊號的結果統計起來（隔天開盤進場、扣成本）。',
                '分組：同一種訊號＋同一種市場狀態；樣本少於 10 次時改用這種訊號在所有市場狀態的統計。',
                '典型走勢區間：買進後第 1／3／5／10／15／20 天的 R 中位數和 25%～75% 範圍；持股落在範圍下方會提醒「落後同類訊號」。',
                '平均是虧損的訊號組合，推薦卡片會警告要更保守。',
              ]),
              sec('持股每日追蹤（最終版 §14、§15）', [
                '從買進那天起每個交易日一筆紀錄：收盤、損益（% 和 R）、停損（有上調會標出）、當天發生的事、持續建議和原因、健康度、持有週期。',
                '持續建議：續抱、續抱但注意、可以加碼、先賣一半、出場、停損出場、應已出場未處理（第 N 天）。',
                '健康度：每天檢查買進理由還成立嗎——守住 20 日線（長期看季線）、趨勢向上、贏過大盤、量價沒有出貨、動能、市場、離停損的緩衝。連續兩天低於 40，跌破停損前就先建議減碼一半。',
                '持有週期每天重估：只有在已經獲利 +1R 以上才會升級；降級隨時發生。虧損中不能把短線改成更長的持有方式。',
                '出場優先順序：風險（停損）＞理由失效＞價格／時間停損＞移動停利。',
                '明日劇本：收盤在哪個價位該停損、警戒、續抱、加碼。',
                '紀律：出場訊號出現後你準時處理、晚處理還是提前賣，統計準時率和晚處理多賠的金額。',
              ]),
              sec('回測（§15）', [
                '推薦和回測用同一套函式；第 t 天收盤訊號、t+1 開盤進場，不偷看未來。',
                '扣手續費、證交稅、滑價；跌停鎖死那天賣不掉。',
                '前段／後段比較、壓力測試（滑價 ×2、成本 ×1.5、晚一天進場）、Monte Carlo 最大回撤。',
              ]),
              sec('還沒做（需要新的資料來源或不適合放在這個 App）', [
                '基本面（§5、最終版 §09～§10）：月營收、財報、估值、股利，要用「實際公告日」避免偷看未來；接上後長期分數才完整，持有期間才可能到 D4／D5。',
                '籌碼（§6）：三大法人、融資融券、借券。',
                '全球風險環境（最終版 §05）、60／15 分鐘盤中週期（§2.1、§9）、事件與 AI 解讀。',
                '自動下單（§13）：需要券商 API 或 MultiCharts，牽涉真實帳戶，不放在這個 App。',
                '投資組合層級：持股相關性、Portfolio Beta、Portfolio Heat（需要實際持股資料）。',
              ], kind: BulletKind.warn),
            ],
          ),
        ),
      ),
    );
  }
}
