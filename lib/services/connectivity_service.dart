import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();

  /// Check if device has active internet connection
  /// Uses connectivity state as primary indicator - more reliable than DNS lookups
  static Future<bool> hasInternetConnection() async {
    try {
      // Check connectivity state (WiFi, Mobile, Ethernet)
      final connectivityResult = await _connectivity.checkConnectivity();
      
      // If no connectivity state, definitely no internet
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false;
      }

      // If connected via WiFi or Mobile, trust it (connectivity_plus is reliable)
      if (connectivityResult.contains(ConnectivityResult.wifi) || 
          connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.ethernet)) {
        return true;
      }

      return false;
    } catch (e) {
      // On any error, assume connected (fail open rather than block user)
      return true;
    }
  }

  /// Get current connectivity status
  static Future<ConnectivityResult> getConnectivityStatus() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.isNotEmpty ? result.first : ConnectivityResult.none;
    } catch (e) {
      return ConnectivityResult.none;
    }
  }

  /// Listen to connectivity changes
  /// Returns a stream of ConnectivityResult
  static Stream<ConnectivityResult> onConnectivityChanged() {
    return _connectivity.onConnectivityChanged.map((results) {
      return results.isNotEmpty ? results.first : ConnectivityResult.none;
    }).handleError((_) {
      return ConnectivityResult.none;
    });
  }
}
