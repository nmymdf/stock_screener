/// 導覽殼：視窗夠寬（電腦）時左邊是側邊選單，窄（手機）時是底部分頁列，
/// 同一份程式碼、同一份畫面。
library;

import 'package:flutter/material.dart';

import 'layout.dart';
import 'screens/backtest_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/holdings_screen.dart';
import 'screens/industry_screen.dart';
import 'screens/market_screen.dart';
import 'screens/portfolio_screen.dart';
import 'screens/shortterm_screen.dart';
import 'screens/tools_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// 從任何畫面切換到某個分頁（例如組合頁的市場環境點下去跳到市場頁）。
  static void goTo(BuildContext context, int index) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(index);

  static const portfolio = 0,
      holdings = 1,
      compare = 2,
      market = 3,
      industry = 4,
      backtest = 5,
      tools = 6,
      shortTerm = 7;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int i) => setState(() => _index = i);

  static const _tabs = [
    (Icons.pie_chart_outline, Icons.pie_chart, '組合'),
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
    1 => const HoldingsScreen(),
    2 => const CompareScreen(),
    3 => const MarketScreen(),
    4 => const IndustryScreen(),
    5 => const BacktestScreen(),
    6 => const ToolsScreen(),
    _ => const ShortTermScreen(),
  };

  @override
  Widget build(BuildContext context) {
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
            NavigationRail(
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
        // 8 個分頁擠在手機底部：只顯示選到的那個的文字
        labelBehavior: width < 520 ? NavigationDestinationLabelBehavior.onlyShowSelected : null,
        destinations: [
          for (final t in _tabs) NavigationDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
