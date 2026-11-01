import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app_state.dart';
import 'core/storage.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    final width = store.prefs.getDouble('windowWidth') ?? 1280;
    final height = store.prefs.getDouble('windowHeight') ?? 860;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(width.clamp(760, 2560), height.clamp(600, 1600)),
        minimumSize: const Size(600, 520),
        center: true,
        title: '创客次元',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    windowManager.addListener(_WindowPersistence(store));
  }
  runApp(
    ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const CTSpaceApp(),
    ),
  );
}

class _WindowPersistence extends WindowListener {
  _WindowPersistence(this.store);
  final LocalStore store;
  @override
  void onWindowResized() async {
    final size = await windowManager.getSize();
    await store.prefs.setDouble('windowWidth', size.width);
    await store.prefs.setDouble('windowHeight', size.height);
  }
}
