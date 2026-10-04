import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/datapack_store.dart';
import 'data/history_store.dart';
import 'data/holdings_store.dart';
import 'data/longterm_store.dart';
import 'data/stock_acc_source.dart';
import 'ui/home.dart';
import 'ui/layout.dart';
import 'ui/theme.dart';
import 'ui/widgets/app_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = HistoryStore(autoSync: true)..load();
  final pack = DataPackStore();
  runApp(
    StockScreenerApp(
      store: store,
      holdings: HoldingsStore(accSource: StockAccSource())..load(),
      pack: pack,
      longTerm: LongTermStore(pack: pack, history: store, autoUpdate: true)..load(),
    ),
  );
}

class StockScreenerApp extends StatelessWidget {
  final HistoryStore store;
  final HoldingsStore holdings;
  final DataPackStore pack;
  final LongTermStore longTerm;
  const StockScreenerApp._(this.store, this.holdings, this.pack, this.longTerm, {super.key});

  /// 測試可以只給 [store]，其他用預設（不連網、不自動更新）。
  factory StockScreenerApp({
    Key? key,
    required HistoryStore store,
    HoldingsStore? holdings,
    DataPackStore? pack,
    LongTermStore? longTerm,
  }) {
    final p = pack ?? DataPackStore();
    return StockScreenerApp._(
      store,
      holdings ?? (HoldingsStore()..load()),
      p,
      longTerm ?? (LongTermStore(pack: p, history: store)..load()),
      key: key,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: holdings),
        ChangeNotifierProvider.value(value: pack),
        ChangeNotifierProvider.value(value: longTerm),
      ],
      child: Builder(
        builder: (context) {
          final themeMode = context.select<HistoryStore, ThemeMode>((s) => s.themeMode);
          final fontScale = context.select<HistoryStore, double?>((s) => s.fontScale);
          return MaterialApp(
            title: '台股選股',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: themeMode,
            // 每個畫面最上面都有抬頭；字體依視窗寬度自動放大（也可以在抬頭手動調整）
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final scale = fontScale ?? autoFontScale(mq.size.width);
              // 放大後的設定要一路傳到下面的每一頁（不能再從外層的 context 重讀，否則會被蓋回原本的大小）
              final scaled = mq.copyWith(textScaler: TextScaler.linear(scale));
              return MediaQuery(
                data: scaled,
                child: Column(
                  children: [
                    const AppBanner(),
                    Expanded(
                      child: MediaQuery(data: scaled.removePadding(removeTop: true), child: child ?? const SizedBox()),
                    ),
                  ],
                ),
              );
            },
            home: const _Root(),
          );
        },
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const HomeShell();
  }
}
