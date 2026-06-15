import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RadioPlaybackGuard {
  static const String _kOfflineModeKey = 'offline_mode';
  static const String _kUseCellularDataKey = 'use_cellular_data';

  static Future<String?> blockingMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final offlineMode = prefs.getBool(_kOfflineModeKey) ?? false;
      if (offlineMode) {
        return 'No internet connection';
      }

      final results = await Connectivity().checkConnectivity();
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) {
        return 'No internet connection';
      }

      final useCellularData = prefs.getBool(_kUseCellularDataKey) ?? true;
      final onWifiLike = results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet) ||
          results.contains(ConnectivityResult.vpn);
      final onMobileOnly =
          results.contains(ConnectivityResult.mobile) && !onWifiLike;

      if (!useCellularData && onMobileOnly) {
        return 'Cellular streaming is turned off in Settings';
      }

      return null;
    } catch (_) {
      // If connectivity probing fails, treat as unavailable to avoid crashes.
      return 'No internet connection';
    }
  }
}
