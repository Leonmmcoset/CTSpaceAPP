import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class LocalStore {
  LocalStore(this.prefs, {FlutterSecureStorage? secure})
    : secure = secure ?? const FlutterSecureStorage();
  final SharedPreferences prefs;
  final FlutterSecureStorage secure;
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
      return await file.exists()
          ? object(jsonDecode(await file.readAsString()))
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(String userId, String key, Json value) async {
    final file = await _draftFile(userId, key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> deleteDraft(String userId, String key) async {
    final file = await _draftFile(userId, key);
    if (await file.exists()) await file.delete();
  }
}
