import 'package:shared_preferences/shared_preferences.dart';

import 'kv_store.dart';

class SharedPrefsKvStore implements KvStore {
  SharedPrefsKvStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPrefsKvStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsKvStore(prefs);
  }

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}

