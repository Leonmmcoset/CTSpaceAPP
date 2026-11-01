import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class LocalStore {
  LocalStore(this.prefs, {FlutterSecureStorage? secure})
    : secure =
          secure ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final SharedPreferences prefs;
  final FlutterSecureStorage secure;
  final Map<String, Future<void>> _writes = {};
  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());
  Future<String?> readToken() => secure.read(key: 'ctspace.session');
  Future<void> writeToken(String? token) => token == null
      ? secure.delete(key: 'ctspace.session')
      : secure.write(key: 'ctspace.session', value: token);
  Future<File> _draftFile(String userId, String key) async {
    final directory = await getApplicationSupportDirectory();
    final safe = '${userId}_$key'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final folder = Directory('${directory.path}/drafts');
    await folder.create(recursive: true);
    return File('${folder.path}/$safe.json');
  }

  Future<Json?> readDraft(String userId, String key) async {
    try {
      final file = await _draftFile(userId, key);
      if (await file.exists())
        return object(jsonDecode(await file.readAsString()));
      final pending = File('${file.path}.tmp');
      return await pending.exists()
          ? object(jsonDecode(await pending.readAsString()))
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _serialize(
    String userId,
    String key,
    Future<void> Function() action,
  ) {
    final identity = '$userId:$key';
    final previous = _writes[identity] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => action());
    _writes[identity] = next;
    return next.whenComplete(() {
      if (identical(_writes[identity], next)) _writes.remove(identity);
    });
  }

  Future<void> saveDraft(String userId, String key, Json value) {
    // Capture before queueing so a later edit cannot mutate this snapshot.
    final encoded = jsonEncode(value);
    return _serialize(userId, key, () async {
      final file = await _draftFile(userId, key);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(encoded, flush: true);
      if (Platform.isWindows && await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
  }

  Future<void> deleteDraft(String userId, String key) =>
      _serialize(userId, key, () async {
        final file = await _draftFile(userId, key);
        for (final candidate in [file, File('${file.path}.tmp')]) {
          if (await candidate.exists()) await candidate.delete();
        }
      });
}
