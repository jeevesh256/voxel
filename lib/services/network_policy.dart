import 'package:shared_preferences/shared_preferences.dart';

class NetworkPolicy {
  static const String offlineModeKey = 'offline_mode';

  static Future<bool> isOfflineModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(offlineModeKey) ?? false;
  }
}
