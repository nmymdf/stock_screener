import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/history_store.dart';
import 'data/holdings_store.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(StockScreenerApp(store: HistoryStore()..load(), holdings: HoldingsStore()..load()));
}

class StockScreenerApp extends StatelessWidget {
  final HistoryStore store;
  final HoldingsStore holdings;
  StockScreenerApp({super.key, required this.store, HoldingsStore? holdings})
    : holdings = holdings ?? (HoldingsStore()..load());

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: holdings),
      ],
      child: MaterialApp(
        title: '台股選股',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const _Root(),
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
