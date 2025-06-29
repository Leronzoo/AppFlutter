import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'models/beacon_device.dart';

class BLEService extends ChangeNotifier {
  final flutterReactiveBle = FlutterReactiveBle();

  static const String targetServiceUuid = "12345678-1234-1234-1234-123456789abc";
  static const String characteristicUuid = "87654321-4321-4321-4321-cba987654321";

  final List<BeaconDevice> _discoveredBeacons = [];
  BeaconDevice? _closestBeacon;
  bool _isScanning = false;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  Timer? _cleanupTimer;

  List<BeaconDevice> get discoveredBeacons => _discoveredBeacons;
  BeaconDevice? get closestBeacon => _closestBeacon;
  bool get isScanning => _isScanning;

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> startScanning() async {
    if (_isScanning) return;

    if (!await requestPermissions()) {
      debugPrint("Permissões negadas");
      return;
    }

    _discoveredBeacons.clear();
    _isScanning = true;
    notifyListeners();

    _scanSubscription = flutterReactiveBle
        .scanForDevices(
          withServices: [], // escaneia tudo, sem filtro direto
          scanMode: ScanMode.lowLatency,
        )
        .listen((device) {
          debugPrint("${device.name} - ${device.id}");
          if (_isMyBeacon(device)) {
            _onDeviceDiscovered(device);
          }
        }, onError: (e) {
          debugPrint("Erro no scan: $e");
        });

    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanOldBeacons(),
    );
  }

bool _isMyBeacon(DiscoveredDevice device) {
  // Verifica se o nome do dispositivo contém "BEACON"
  if (device.name.toUpperCase().contains("BEACON")) return true;

  // Tenta verificar o manufacturerData, mas ignora se der erro
  try {
    final data = utf8.decode(device.manufacturerData);
    return data.toUpperCase().contains("BEACON");
  } catch (_) {
    return false;
  }
}

  void _onDeviceDiscovered(DiscoveredDevice device) {
    final id = device.id;
    final name = device.name.isNotEmpty ? device.name : "Beacon Desconhecido";
    final distance = BeaconDevice.calculateDistance(device.rssi, -59);

    final beacon = BeaconDevice(
      id: id,
      name: name,
      rssi: device.rssi,
      serviceUuid: targetServiceUuid,
      lastSeen: DateTime.now(),
      distance: distance,
      data: {
        "manufacturerData": device.manufacturerData,
      },
    );

    _updateBeaconList(beacon);
  }

  void _updateBeaconList(BeaconDevice beacon) {
    final index = _discoveredBeacons.indexWhere((b) => b.id == beacon.id);
    if (index != -1) {
      _discoveredBeacons[index] = beacon;
    } else {
      _discoveredBeacons.add(beacon);
    }
    _updateClosestBeacon();
    notifyListeners();
  }

  void _updateClosestBeacon() {
    if (_discoveredBeacons.isEmpty) {
      _closestBeacon = null;
    } else {
      _discoveredBeacons.sort((a, b) => b.rssi.compareTo(a.rssi));
      _closestBeacon = _discoveredBeacons.first;
    }
  }

  void _cleanOldBeacons() {
    final threshold = DateTime.now().subtract(const Duration(seconds: 30));
    _discoveredBeacons.removeWhere((b) => b.lastSeen.isBefore(threshold));
    _updateClosestBeacon();
    notifyListeners();
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    await _scanSubscription?.cancel();
    _cleanupTimer?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> connectAndReadData(String deviceId) async {
    try {
      final connection = flutterReactiveBle.connectToDevice(id: deviceId);
      final completer = Completer<Map<String, dynamic>>();
      late StreamSubscription<ConnectionStateUpdate> sub;

      sub = connection.listen((connectionState) async {
        if (connectionState.connectionState == DeviceConnectionState.connected) {
          final characteristic = QualifiedCharacteristic(
            deviceId: deviceId,
            serviceId: Uuid.parse(targetServiceUuid),
            characteristicId: Uuid.parse(characteristicUuid),
          );

          final value = await flutterReactiveBle.readCharacteristic(characteristic);
          await sub.cancel();
          completer.complete(json.decode(utf8.decode(value)) as Map<String, dynamic>);
        }
      }, onError: (e) async {
        await sub.cancel();
        completer.completeError(e);
      });

      return await completer.future;
    } catch (e) {
      debugPrint("Erro ao conectar/ler dados: $e");
      return null;
    }
  }

  @override
  void dispose() {
    stopScanning();
    super.dispose();
  }
}
