/// 導覽殼：視窗夠寬（電腦）時左邊是側邊選單，窄（手機）時是底部分頁列，
/// 同一份程式碼、同一份畫面。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/history_store.dart';
import 'widgets/common.dart';

import 'layout.dart';
import 'screens/backtest_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/holdings_screen.dart';
import 'screens/industry_screen.dart';
import 'screens/market_screen.dart';
import 'screens/marketcap_screen.dart';
import 'screens/portfolio_screen.dart';
import 'screens/shortterm_screen.dart';
import 'screens/tools_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// 從任何畫面切換到某個分頁（例如組合頁的市場環境點下去跳到市場頁）。
  static void goTo(BuildContext context, int index) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(index);

  static const portfolio = 0,
      marketCap = 1,
      holdings = 2,
      compare = 3,
      market = 4,
      industry = 5,
      backtest = 6,
      tools = 7,
      shortTerm = 8;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _asking = false;

  /// 第一次打開（還沒同意過免責聲明）就跳出來。
  void _askDisclaimer(HistoryStore store) {
    if (_asking || !store.loaded || store.disclaimerAccepted) return;
    _asking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await showDisclaimerDialog(context)) await store.acceptDisclaimer();
      _asking = false;
    });
  }

  void _select(int i) => setState(() => _index = i);

  static const _tabs = [
    (Icons.pie_chart_outline, Icons.pie_chart, '組合'),
    (Icons.leaderboard_outlined, Icons.leaderboard, '市值'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, '持股'),
    (Icons.compare_arrows_outlined, Icons.compare_arrows, '比較'),
    (Icons.speed_outlined, Icons.speed, '市場'),
    (Icons.category_outlined, Icons.category, '產業'),
    (Icons.science_outlined, Icons.science, '回測'),
    (Icons.build_outlined, Icons.build, '工具'),
    (Icons.bolt_outlined, Icons.bolt, '短線'),
  ];

  Widget _body() => switch (_index) {
    0 => const PortfolioScreen(),
    1 => const MarketCapScreen(),
    2 => const HoldingsScreen(),
    3 => const CompareScreen(),
    4 => const MarketScreen(),
    5 => const IndustryScreen(),
    6 => const BacktestScreen(),
    7 => const ToolsScreen(),
    _ => const ShortTermScreen(),
  };

  @override
  Widget build(BuildContext context) {
    _askDisclaimer(context.watch<HistoryStore>());
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: _body(),
      ),
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            // 視窗矮的時候 9 個分頁放不下：讓側邊選單可以捲動
            LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: _index,
                      extended: width >= 1280,
                      minExtendedWidth: 168,
                      labelType: width >= 1280 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                      onDestinationSelected: _select,
                      destinations: [
                        for (final t in _tabs)
                          NavigationRailDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: Text(t.$3)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        // 9 個分頁擠在手機底部：只顯示選到的那個的文字
        labelBehavior: width < 520 ? NavigationDestinationLabelBehavior.onlyShowSelected : null,
        destinations: [
          for (final t in _tabs) NavigationDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
