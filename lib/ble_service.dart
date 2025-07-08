import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models/beacon_device.dart';

const String servidorIp = "http://172.22.170.20"; // IP do servidor PHP

class BLEService extends ChangeNotifier {
  final flutterReactiveBle = FlutterReactiveBle();
  final FlutterTts _flutterTts = FlutterTts();

  static const String targetServiceUuid = "12345678-1234-1234-1234-123456789abc";
  static const String characteristicUuid = "87654321-4321-4321-4321-cba987654321";

  final Duration _intervaloFala = const Duration(seconds: 5);
  final Duration _intervaloCache = const Duration(hours: 1);

  final List<BeaconDevice> _discoveredBeacons = [];
  final Map<String, String> _respostas = {};
  BeaconDevice? _maisProximo;

  bool _isScanning = false;
  String? _ultimoFaladoId;
  DateTime _ultimoFaladoTime = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  Timer? _cleanupTimer;

  List<BeaconDevice> get discoveredBeacons => _discoveredBeacons;
  BeaconDevice? get closestBeacon => _maisProximo;
  bool get isScanning => _isScanning;

  BLEService() {
    _carregarCache();
  }

  Future<void> _carregarCache() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('beacon_cache');
    final tempo = prefs.getString('beacon_cache_timestamp');
    final agora = DateTime.now();
    final ultima = tempo != null ? DateTime.tryParse(tempo) : null;

    if (dados != null && ultima != null && agora.difference(ultima) < _intervaloCache) {
      _respostas.addAll(Map<String, String>.from(jsonDecode(dados)));
    } else {
      await _atualizarDoServidor();
    }
  }

  Future<void> _atualizarDoServidor() async {
    try {
      final response = await http.get(Uri.parse("$servidorIp/api/listar.php"));
      if (response.statusCode == 200) {
        final List jsonList = jsonDecode(response.body);
        _respostas.clear();
        for (final item in jsonList) {
          final id = item['beacon_id'];
          final resposta = item['resposta'];
          if (id != null && resposta != null) {
            _respostas[id.toString().toLowerCase()] = resposta.toString();
          }
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('beacon_cache', jsonEncode(_respostas));
        await prefs.setString('beacon_cache_timestamp', DateTime.now().toIso8601String());
      }
    } catch (_) {
      // Se erro, mantém cache antigo
    }
  }

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
    if (!await requestPermissions()) return;

    _discoveredBeacons.clear();
    _isScanning = true;
    notifyListeners();

    _scanSubscription = flutterReactiveBle
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen((device) {
      if (_ehBeaconValido(device)) _processar(device);
    });

    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _limparAntigos(),
    );
  }

  bool _ehBeaconValido(DiscoveredDevice device) {
    if (device.name.toUpperCase().contains("BEACON")) return true;
    try {
      final data = utf8.decode(device.manufacturerData);
      return data.toUpperCase().contains("BEACON");
    } catch (_) {
      return false;
    }
  }

  void _processar(DiscoveredDevice device) {
    final beacon = BeaconDevice(
      id: device.id,
      name: device.name.isNotEmpty ? device.name : "Desconhecido",
      rssi: device.rssi,
      serviceUuid: targetServiceUuid,
      lastSeen: DateTime.now(),
      distance: BeaconDevice.calculateDistance(device.rssi, -59),
      data: {
        "manufacturerData": device.manufacturerData,
      },
    );

    final index = _discoveredBeacons.indexWhere((b) => b.id == beacon.id);
    if (index != -1) {
      _discoveredBeacons[index] = beacon;
    } else {
      _discoveredBeacons.add(beacon);
    }

    _atualizarMaisProximo();
    notifyListeners();
  }

void _atualizarMaisProximo() {
  if (_discoveredBeacons.isEmpty) {
    _maisProximo = null;
    return;
  }

  _discoveredBeacons.sort((a, b) => b.rssi.compareTo(a.rssi));
  _maisProximo = _discoveredBeacons.first;

  final agora = DateTime.now();

  // Continua apenas se mudou o beacon mais próximo e passou o tempo mínimo
  if (_maisProximo!.id != _ultimoFaladoId &&
      agora.difference(_ultimoFaladoTime) > _intervaloFala) {
    _ultimoFaladoId = _maisProximo!.id;
    _ultimoFaladoTime = agora;

    // Normaliza o ID detectado (remove dois pontos e coloca minúsculo)
    final idNormalizado = _maisProximo!.id.toLowerCase().replaceAll(":", "");

    // Procura uma chave no Map que bata com esse ID (também normalizando)
    final matchedKey = _respostas.keys.firstWhere(
      (key) => key.toLowerCase().replaceAll(":", "") == idNormalizado,
      orElse: () => '',
    );

    final texto = matchedKey.isNotEmpty
        ? _respostas[matchedKey]!
        : "Beacon sem resposta definida";

    print("Beacon detectado: ${_maisProximo!.id}");
    print("Texto falado: $texto");

    _flutterTts.setLanguage("pt-BR");
    _flutterTts.setSpeechRate(0.9);
    _flutterTts.speak(texto);
  }
}


  void _limparAntigos() {
    final limite = DateTime.now().subtract(const Duration(seconds: 30));
    _discoveredBeacons.removeWhere((b) => b.lastSeen.isBefore(limite));
    _atualizarMaisProximo();
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    await _scanSubscription?.cancel();
    _cleanupTimer?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopScanning();
    super.dispose();
  }
}
