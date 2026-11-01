import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum/core/api.dart';
import 'package:forum/core/models.dart';
import 'package:forum/core/pow.dart';

class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.handle);
  final ResponseBody Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handle(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  test('PoW returns a valid nonce for the documented SHA-256 contract', () {
    final nonce = solveProofOfWork({
      'challenge': 'ctspace-test',
      'difficulty': 2,
    });
    expect(
      sha256.convert(utf8.encode('ctspace-test:$nonce')).toString(),
      startsWith('00'),
    );
    expect(
      () => solveProofOfWork({'challenge': 'x', 'difficulty': 99}),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('pagination accepts both server pages and unpaginated lists', () {
    final result = PageResult.fromJson({
      'items': [
        {'id': 'a'},
      ],
      'total': 30,
      'page': 1,
      'pageSize': 24,
    }, (e) => e['id']);
    expect(result.items, ['a']);
    expect(result.hasMore, isTrue);
    expect(
      PageResult.fromJson([
        {'id': 'b'},
      ], (e) => e['id']).hasMore,
      isFalse,
    );
  });
  test('relative resources resolve against the site rather than /api', () {
    expect(
      absoluteUrl('/uploads/中文.sb3'),
      'https://forum.ctspace.xyz/uploads/%E4%B8%AD%E6%96%87.sb3',
    );
    expect(
      absoluteUrl('https://example.org/a.png'),
      'https://example.org/a.png',
    );
    expect(absoluteUrl('data:image/png;base64,AA'), 'data:image/png;base64,AA');
  });
  test(
    'authenticated API requests attach tokens only to the configured origin',
    () async {
      final dio = Dio(BaseOptions(baseUrl: apiBase));
      var authorized = false;
      dio.httpClientAdapter = StubAdapter((o) {
        authorized = o.headers['Authorization'] == 'Bearer secret';
        return ResponseBody.fromString(
          '{"items":[]}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
      final api = ApiClient(transport: dio)..token = 'secret';
      await api.get('/discussions');
      expect(authorized, isTrue);
      await dio.get('https://example.org/public');
      expect(authorized, isFalse);
    },
  );
  test('failed write requests are never automatically repeated', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(baseUrl: apiBase));
    dio.httpClientAdapter = StubAdapter((o) {
      calls++;
      throw DioException.connectionTimeout(
        requestOptions: o,
        timeout: const Duration(seconds: 1),
      );
    });
    final api = ApiClient(transport: dio);
    await expectLater(
      api.post('/shop/checkout', {'productId': 'x'}),
      throwsA(
        isA<ApiFailure>().having((e) => e.uncertain, 'uncertain', isTrue),
      ),
    );
    expect(calls, 1);
  });
  test(
    'expired sessions clear auth while a rejected login preserves its error',
    () async {
      final dio = Dio(BaseOptions(baseUrl: apiBase));
      dio.httpClientAdapter = StubAdapter(
        (o) => ResponseBody.fromString(
          '{"message":"账号未激活"}',
          401,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      var expired = 0;
      final api = ApiClient(transport: dio)
        ..token = 'old'
        ..onUnauthorized = () {
          expired++;
        };
      await expectLater(api.post('/auth/login'), throwsA(isA<ApiFailure>()));
      expect(expired, 0);
      await expectLater(api.get('/auth/me'), throwsA(isA<ApiFailure>()));
      expect(expired, 1);
    },
  );
}
