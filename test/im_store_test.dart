import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum/core/api.dart';
import 'package:forum/core/im_store.dart';
import 'package:forum/core/models.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final Json Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(handle(options)),
    200,
    headers: {
      'content-type': ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'reconnect merges unordered duplicates and recall patches without losing fields',
    () {
      final merged = mergeMessages(
        [
          {
            'id': 'b',
            'createdAt': '2026-01-02',
            'content': '二',
            'senderId': 'u',
          },
          {'id': 'a', 'createdAt': '2026-01-01', 'content': '一'},
        ],
        [
          {'id': 'b', 'recalledAt': '2026-01-03'},
          {'id': 'c', 'createdAt': '2026-01-02', 'content': '三'},
          {'id': 'a', 'createdAt': '2026-01-01', 'content': '更新'},
        ],
      );
      expect(merged.map((e) => e['id']), ['a', 'b', 'c']);
      expect(merged[0]['content'], '更新');
      expect(merged[1]['recalledAt'], '2026-01-03');
      expect(merged[1]['senderId'], 'u');
    },
  );

  test('message paging honors total on a full final page', () {
    final rows = List.generate(20, (i) => {'id': '$i'});
    expect(
      messagePageHasMore({'items': rows, 'total': 20, 'pageSize': 20}, 1),
      false,
    );
    expect(
      messagePageHasMore({'items': rows, 'total': 21, 'pageSize': 20}, 1),
      true,
    );
    expect(messagePageHasMore({'items': rows}, 1), true);
    expect(messagePageHasMore({'items': []}, 2), false);
  });

  test(
    'reconnect fetches missed pages until it reaches existing history',
    () async {
      final pages = <int>[];
      final dio = Dio(BaseOptions(baseUrl: apiBase));
      dio.httpClientAdapter = _Adapter((o) {
        if (!o.path.endsWith('/messages')) return {};
        final page = o.queryParameters['page'] as int;
        pages.add(page);
        return {
          'items': page == 1
              ? [
                  {'id': 'c', 'createdAt': '2026-01-03'},
                ]
              : [
                  {'id': 'b', 'createdAt': '2026-01-02'},
                  {'id': 'a', 'createdAt': '2026-01-01'},
                ],
          'pageSize': 1,
          'total': 3,
        };
      });
      final store = ImStore(ApiClient(transport: dio))
        ..current = const Conversation(kind: 'dm', id: 'thread', title: '对话')
        ..messages = [
          {'id': 'a', 'createdAt': '2026-01-01'},
        ];
      await store.resync();
      expect(pages, [1, 2]);
      expect(store.messages.map((e) => e['id']), ['a', 'b', 'c']);
      store.dispose();
    },
  );
}
