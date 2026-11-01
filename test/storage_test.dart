import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:forum/core/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'draft writes preserve order, snapshots and account isolation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ctspace-storage-',
      );
      final original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      try {
        final mutable = {'title': '第一版'};
        final first = store.saveDraft('one', 'discussion', mutable);
        mutable['title'] = '后续修改';
        await first;
        expect((await store.readDraft('one', 'discussion'))?['title'], '第一版');
        await Future.wait([
          for (var i = 0; i < 12; i++)
            store.saveDraft('one', 'discussion', {'revision': i}),
          store.saveDraft('two', 'discussion', {'title': '另一个账号'}),
        ]);
        expect((await store.readDraft('one', 'discussion'))?['revision'], 11);
        expect((await store.readDraft('two', 'discussion'))?['title'], '另一个账号');
        final pending = store.saveDraft('one', 'discussion', {'title': '发布前'});
        final deleted = store.deleteDraft('one', 'discussion');
        await Future.wait([pending, deleted]);
        expect(await store.readDraft('one', 'discussion'), isNull);
        await store.writeToken('test-session');
        await store.writeToken(null);
        expect((await store.readDraft('two', 'discussion'))?['title'], '另一个账号');
        expect(store.prefs.getKeys(), isEmpty);
      } finally {
        PathProviderPlatform.instance = original;
        await directory.delete(recursive: true);
      }
    },
  );
}
