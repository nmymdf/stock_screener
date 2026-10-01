/// 導覽殼：視窗夠寬（電腦）時左邊是側邊選單，窄（手機）時是底部分頁列，
/// 同一份程式碼、同一份畫面。
library;

import 'package:flutter/material.dart';

import 'screens/backtest_screen.dart';
import 'screens/holdings_screen.dart';
import 'screens/industry_screen.dart';
import 'screens/market_screen.dart';
import 'screens/recommend_screen.dart';
import 'screens/tools_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// 從任何畫面切換到某個分頁（例如推薦頁上的市場橫幅點下去跳到市場頁）。
  static void goTo(BuildContext context, int index) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(index);

  static const recommend = 0, holdings = 1, market = 2, industry = 3, backtest = 4, tools = 5;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int i) => setState(() => _index = i);

  static const _tabs = [
    (Icons.star_outline, Icons.star, '推薦'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, '持股'),
    (Icons.speed_outlined, Icons.speed, '市場'),
    (Icons.category_outlined, Icons.category, '產業'),
    (Icons.science_outlined, Icons.science, '回測'),
    (Icons.build_outlined, Icons.build, '工具'),
  ];

  Widget _body() => switch (_index) {
    0 => const RecommendScreen(),
    1 => const HoldingsScreen(),
    2 => const MarketScreen(),
    3 => const IndustryScreen(),
    4 => const BacktestScreen(),
    _ => const ToolsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: _body()),
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              labelType: NavigationRailLabelType.all,
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
        destinations: [
          for (final t in _tabs) NavigationDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
