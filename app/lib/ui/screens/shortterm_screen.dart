/// 「短線」：放在最右邊的獨立分頁，給喜歡短線的朋友，或挑長期股票的進場時機參考。
/// 短線訊號（A／B／C／D）、今日即時雷達、自訂條件篩選。
library;

import 'package:flutter/material.dart';

import 'radar_screen.dart';
import 'recommend_screen.dart';
import 'technical_screen.dart';

class ShortTermScreen extends StatelessWidget {
  const ShortTermScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.bolt, size: 20), text: '短線訊號'),
                Tab(icon: Icon(Icons.radar, size: 20), text: '今日雷達'),
                Tab(icon: Icon(Icons.filter_alt_outlined, size: 20), text: '自訂篩選'),
              ],
            ),
          ),
          const Expanded(child: TabBarView(children: [RecommendScreen(), RadarScreen(), TechnicalScreen()])),
        ],
      ),
    );
  }
}
