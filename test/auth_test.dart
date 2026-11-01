import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum/core/api.dart';
import 'package:forum/core/app_state.dart';
import 'package:forum/features/auth.dart';

class _CaptchaApi implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    expect(options.method, 'GET');
    expect(options.path, '/captcha');
    return ResponseBody.fromString(
      jsonEncode({
        'token': 'captcha-token',
        'image': '',
        'pow': {'challenge': 'test-challenge', 'difficulty': 0},
      }),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('captcha preserves six typed or pasted characters in the proof', (
    tester,
  ) async {
    final dio = Dio(BaseOptions(baseUrl: apiBase))
      ..httpClientAdapter = _CaptchaApi();
    addTearDown(() => dio.close(force: true));
    final captcha = GlobalKey<CaptchaInputState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(ApiClient(transport: dio))],
        child: MaterialApp(
          home: Scaffold(body: CaptchaInput(key: captcha)),
        ),
      ),
    );
    await tester.runAsync(() => captcha.currentState!.refresh());
    await tester.pumpAndSettle();

    const answer = 'Ab12Cd';
    for (var length = 1; length <= answer.length; length++) {
      await tester.enterText(
        find.byType(TextFormField),
        answer.substring(0, length),
      );
    }
    expect(captcha.currentState!.value?.toJson(), {
      'captchaToken': 'captcha-token',
      'captchaAnswer': answer,
      'captchaPowNonce': '0',
    });

    await tester.enterText(find.byType(TextFormField), 'Z9y8X7');
    expect(captcha.currentState!.value?.answer, 'Z9y8X7');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
