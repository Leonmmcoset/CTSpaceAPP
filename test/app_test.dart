import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum/app.dart';
import 'package:forum/core/api.dart';
import 'package:forum/core/app_state.dart';
import 'package:forum/core/storage.dart';
import 'package:forum/core/models.dart';
import 'package:forum/features/composer.dart';
import 'package:forum/ui/shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

const discussion = {
  'id': 'd1',
  'title': '用积木搭建一个新世界',
  'content': '你好，创客次元。',
  'seq': 1,
  'author': {'id': 'u1', 'username': 'maker', 'nickname': '创作者'},
  'tags': [],
  'posts': [],
  'createdAt': '2026-10-01T00:00:00Z',
};

class _Api implements HttpClientAdapter {
  int writes = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (o.method != 'GET') {
      writes++;
      throw StateError('UI smoke tests must remain read only');
    }
    if (o.path == '/captcha')
      return ResponseBody.fromString(
        '{"message":"验证码暂不可用"}',
        503,
        headers: {
          'content-type': ['application/json'],
        },
      );
    final dynamic data = switch (o.path) {
      '/tags' => [
        {'id': 't1', 'name': '创作'},
      ],
      '/discussions' => {
        'items': [discussion],
        'total': 1,
        'page': 1,
        'pageSize': 24,
      },
      '/discussions/d1' => discussion,
      '/stats/public' => {'users': 23, 'posts': 42, 'discussions': 12},
      '/origmark/verify/OM-TEST' => {
        'verified': true,
        'title': '原创作品',
        'certNumber': 'OM-TEST',
        'status': 'certified',
      },
      '/live/current' => {'session': null},
      '/resources' || '/comments' => [],
      _ => {'items': [], 'total': 0},
    };
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DraftStore extends LocalStore {
  _DraftStore(super.prefs);
  Json? snapshot;
  @override
  Future<Json?> readDraft(String userId, String key) async => snapshot;
  @override
  Future<void> saveDraft(String userId, String key, Json value) async {
    snapshot = jsonDecode(jsonEncode(value)) as Json;
  }
}

Future<({ProviderContainer container, _Api transport, LocalStore store})>
launch(WidgetTester tester, Size size, {LocalStore? localStore}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final store = localStore ?? LocalStore(await SharedPreferences.getInstance());
  final transport = _Api();
  final dio = Dio(BaseOptions(baseUrl: apiBase))..httpClientAdapter = transport;
  final app = AppState(store, client: ApiClient(transport: dio))
    ..initializing = false;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        appProvider.overrideWith((ref) => app),
      ],
      child: const CTSpaceApp(),
    ),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(CTSpaceApp));
  return (
    container: ProviderScope.containerOf(context),
    transport: transport,
    store: store,
  );
}

void main() {
  testWidgets(
    'phone navigation reaches Chinese feature screens without overflow',
    (tester) async {
      final setup = await launch(tester, const Size(390, 844));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('用积木搭建一个新世界'), findsOneWidget);
      final router = setup.container.read(routerProvider);
      for (final route in [
        '/gallery',
        '/discover',
        '/messages',
        '/me',
        '/settings',
        '/search',
        '/assets',
        '/games',
        '/support',
        '/decoration',
        '/origmark',
        '/origmark/verify?cert=OM-TEST',
        '/live',
        '/login',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
      }
      expect(setup.transport.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('desktop shows sidebar and opens discussions in a second pane', (
    tester,
  ) async {
    final setup = await launch(tester, const Size(1360, 900));
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('开发者工具'), findsOneWidget);
    await tester.tap(find.text('用积木搭建一个新世界'));
    await tester.pumpAndSettle();
    expect(find.text('你好，创客次元。'), findsWidgets);
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(setup.transport.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact phone supports larger text and reduced motion', (
    tester,
  ) async {
    final setup = await launch(tester, const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final router = setup.container.read(routerProvider);
    for (final route in ['/', '/discover', '/me']) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: route);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the editor immediately preserves the last input', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final draftStore = _DraftStore(await SharedPreferences.getInstance());
    final setup = await launch(
      tester,
      const Size(390, 844),
      localStore: draftStore,
    );
    final router = setup.container.read(routerProvider);
    router.push('/compose', extra: const ComposeRequest('discussion'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      if (find.byType(TextField).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, '尚未触发防抖保存的标题');
    router.pop();
    await tester.pumpAndSettle();
    expect(draftStore.snapshot?['title'], '尚未触发防抖保存的标题');
    await tester.pumpWidget(const SizedBox());
  });
}
