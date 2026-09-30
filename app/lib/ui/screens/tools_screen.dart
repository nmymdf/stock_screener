/// 「工具」：自訂條件篩選、今日即時雷達、資金與風險設定、資料管理、方法說明。
library;

import 'package:flutter/material.dart';

import '../../app_build_info.dart';
import '../widgets/score_widgets.dart';
import 'data_screen.dart';
import 'radar_screen.dart';
import 'risk_settings_screen.dart';
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
          Icons.account_balance_wallet_outlined,
          '資金與風險設定',
          '總資金、單筆風險、單檔上限、回撤——決定建議張數',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RiskSettingsScreen())),
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
                '張數＝可承受損失 ÷ 每股風險（含滑價），再受單檔曝險上限限制；帳戶回撤越大，每筆風險自動降低。',
                '可接受最高買價＝收盤 + 0.5 ATR，隔天開盤超過就不追。收漲停的股票會提醒可能買不到。',
              ]),
              sec('回測（§15）', [
                '推薦和回測用同一套函式；第 t 天收盤訊號、t+1 開盤進場，不偷看未來。',
                '扣手續費、證交稅、滑價；跌停鎖死那天賣不掉。',
                '前段／後段比較、壓力測試（滑價 ×2、成本 ×1.5、晚一天進場）、Monte Carlo 最大回撤。',
              ]),
              sec('還沒做（需要新的資料來源或不適合放在這個 App）', [
                '基本面（§5）：月營收、財報、估值，要用「實際公告日」避免偷看未來。',
                '籌碼（§6）：三大法人、融資融券、借券。',
                '全球風險環境（§2.4）、60／15 分鐘盤中週期（§2.1、§9）。',
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
