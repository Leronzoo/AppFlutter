import 'dart:math' as math;

class BeaconDevice {
  final String id;
  final String name;
  final int rssi;
  final String serviceUuid;
  final DateTime lastSeen;
  final double distance;
  final Map<String, dynamic>? data;

  BeaconDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.serviceUuid,
    required this.lastSeen,
    required this.distance,
    this.data,
  });

  static double calculateDistance(int rssi, int txPower) {
    if (rssi == 0) return -1.0;
    double ratio = rssi * 1.0 / txPower;
    if (ratio < 1.0) {
      return math.pow(ratio, 10).toDouble();
    } else {
      return 0.89976 * math.pow(ratio, 7.7095) + 0.111;
    }
  }
}
