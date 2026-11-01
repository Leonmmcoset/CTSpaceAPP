import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'models.dart';
import 'storage.dart';

final storeProvider = Provider<LocalStore>((ref) => throw UnimplementedError());
final appProvider = ChangeNotifierProvider<AppState>(
  (ref) => AppState(ref.watch(storeProvider))..initialize(),
);
final apiProvider = Provider<ApiClient>((ref) => ref.watch(appProvider).api);

final decorationProvider = FutureProvider<Json>((ref) async {
  ref.watch(appProvider.select((a) => a.user?.id));
  return object(await ref.read(apiProvider).get('/deco/catalog'));
});

class AppState extends ChangeNotifier {
  AppState(this.store, {ApiClient? client}) : api = client ?? ApiClient() {
    api.onUnauthorized = () {
      unawaited(signOut());
    };
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == store.prefs.getString('theme'),
      orElse: () => ThemeMode.system,
    );
    dynamicColor = store.prefs.getBool('dynamicColor') ?? false;
    seed = Color(store.prefs.getInt('seed') ?? 0xff7056e8);
  }
  final LocalStore store;
  final ApiClient api;
  Member? user;
  Json settings = {};
  late ThemeMode themeMode;
  late bool dynamicColor;
  late Color seed;
  bool initializing = true;
  int revision = 0;
  String? sessionError;
  bool get signedIn => user != null;
  Future<void> initialize() async {
    final settingsFuture = loadSettings();
    try {
      api.token = store.prefs.getBool('sessionRevoked') == true
          ? null
          : await store.readToken();
      if (api.token != null) {
        try {
          user = Member(object(await api.get('/auth/me')));
        } on ApiFailure catch (e) {
          if (e.status == 401) {
            await store.writeToken(null);
            api.token = null;
          } else {
            sessionError = e.message;
          }
        }
      }
    } catch (_) {
      sessionError = '无法访问系统安全存储';
    }
    await settingsFuture;
    initializing = false;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    try {
      settings = object(await api.get('/settings'));
    } catch (_) {
      /* Offline browsing remains available. */
    }
  }

  Future<Json?> signIn(Json credentials) async {
    final result = object(await api.post('/auth/login', credentials));
    if (result['needSecurityAnswer'] == true) return result;
    await acceptSession(result);
    return null;
  }

  Future<void> answerSecurity(String ticket, String answer) async {
    final result = object(
      await api.post('/auth/login/security', {
        'ticket': ticket,
        'answer': answer,
      }),
    );
    await acceptSession(result);
  }

  Future<void> acceptSession(Json result) async {
    final token = textOf(result['token']);
    if (token.isEmpty) throw const ApiFailure('登录响应异常，请重试');
    try {
      await store.writeToken(token);
      await store.prefs.setBool('sessionRevoked', false);
    } catch (_) {
      throw const ApiFailure('系统安全存储不可用，无法保存登录状态');
    }
    api.token = token;
    user = Member(result['user'] is Map ? object(result['user']) : result);
    sessionError = null;
    changed();
  }

  Future<void> refreshUser() async {
    final session = api.token;
    if (session == null) return;
    try {
      final result = object(await api.get('/auth/me'));
      if (api.token != session) return;
      user = Member(result);
      sessionError = null;
      changed();
    } catch (e) {
      sessionError = friendlyError(e);
    }
  }

  Future<void> signOut() async {
    api.token = null;
    user = null;
    await store.prefs.setBool('sessionRevoked', true);
    try {
      await store.writeToken(null);
    } catch (_) {
      /* Token already cleared in memory. */
    }
    changed();
  }

  void changed() {
    revision++;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await store.prefs.setString('theme', mode.name);
  }

  Future<void> setDynamicColor(bool enabled) async {
    dynamicColor = enabled;
    notifyListeners();
    await store.prefs.setBool('dynamicColor', enabled);
  }

  Future<void> setSeed(Color color) async {
    seed = color;
    notifyListeners();
    await store.prefs.setInt('seed', color.toARGB32());
  }
}
