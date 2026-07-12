import 'package:shared_preferences/shared_preferences.dart';

class NetworkPolicy {
  static Future<bool> isOfflineModeEnabled() async => false;
}
