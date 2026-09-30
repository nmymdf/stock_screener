/// 導覽殼：視窗夠寬（電腦）時左邊是側邊選單，窄（手機）時是底部分頁列，
/// 同一份程式碼、同一份畫面。
library;

import 'package:flutter/material.dart';

import 'screens/data_screen.dart';
import 'screens/radar_screen.dart';
import 'screens/technical_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    (Icons.filter_alt_outlined, Icons.filter_alt, '技術選股'),
    (Icons.radar_outlined, Icons.radar, '今日雷達'),
    (Icons.storage_outlined, Icons.storage, '資料'),
  ];

  Widget _body() => switch (_index) {
        0 => const TechnicalScreen(),
        1 => const RadarScreen(),
        _ => const DataScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: _body()),
    );
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final t in _tabs)
                NavigationRailDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: Text(t.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs) NavigationDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
