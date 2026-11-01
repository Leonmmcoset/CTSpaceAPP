import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forum/core/api.dart';
import 'package:forum/core/app_state.dart';
import 'package:forum/core/storage.dart';

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async => ResponseBody.fromString(
    jsonEncode(
      o.path == '/auth/login'
          ? {
              'needSecurityAnswer': true,
              'ticket': 'challenge',
              'question': '安全问题',
            }
          : {
              'token': 'session',
              'user': {'id': 'u', 'username': 'maker'},
            },
    ),
    200,
    headers: {
      'content-type': ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('security challenge does not create a session until answered', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final dio = Dio(BaseOptions(baseUrl: apiBase))
      ..httpClientAdapter = _Adapter();
    final store = LocalStore(await SharedPreferences.getInstance());
    final app = AppState(store, client: ApiClient(transport: dio));
    final challenge = await app.signIn({
      'username': 'maker',
      'password': 'example',
    });
    expect(challenge?['ticket'], 'challenge');
    expect(app.signedIn, false);
    expect(await store.readToken(), isNull);
    await app.answerSecurity('challenge', 'answer');
    expect(app.user?.id, 'u');
    expect(await store.readToken(), 'session');
    await app.signOut();
    expect(app.api.token, isNull);
    expect(app.user, isNull);
    expect(await store.readToken(), isNull);
    expect(store.prefs.getBool('sessionRevoked'), true);
    app.dispose();
  });
}
