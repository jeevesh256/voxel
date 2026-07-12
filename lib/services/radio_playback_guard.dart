import 'package:connectivity_plus/connectivity_plus.dart';

class RadioPlaybackGuard {
  static Future<String?> blockingMessage() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) {
        return 'No internet connection';
      }
      return null;
    } catch (_) {
      // If connectivity probing fails, treat as unavailable to avoid crashes.
      return 'No internet connection';
    }
  }
}
