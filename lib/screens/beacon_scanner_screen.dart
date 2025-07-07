import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../models/beacon_device.dart';
import 'package:flutter_tts/flutter_tts.dart';

class BeaconScannerScreen extends StatefulWidget {
  const BeaconScannerScreen({super.key});

  @override
  State<BeaconScannerScreen> createState() => _BeaconScannerScreenState();
}

class _BeaconScannerScreenState extends State<BeaconScannerScreen> {
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BLEService>().startScanning();
    });
  }

  @override
  void dispose() {
    context.read<BLEService>().stopScanning();
    super.dispose();
  }

  Future<void> _falarTeste() async {
    await _flutterTts.setLanguage("pt-BR");
    await _flutterTts.setSpeechRate(0.9);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.speak("Teste de voz funcionando");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner de Beacons BLE'),
        actions: [
          Consumer<BLEService>(
            builder: (context, bleService, child) {
              return IconButton(
                icon: Icon(bleService.isScanning ? Icons.stop : Icons.play_arrow),
                onPressed: () {
                  if (bleService.isScanning) {
                    bleService.stopScanning();
                  } else {
                    bleService.startScanning();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Consumer<BLEService>(
        builder: (context, bleService, child) {
          return Column(
            children: [
              if (bleService.closestBeacon != null)
                _buildClosestBeaconCard(bleService.closestBeacon!),
              ElevatedButton(
                onPressed: _falarTeste,
                child: const Text("Testar Voz"),
              ),
              Expanded(child: _buildBeaconList(bleService)),
              _buildStatusBar(bleService),
            ],
          );
        },
      ),
    );
  }

  Widget _buildClosestBeaconCard(BeaconDevice beacon) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        color: Colors.green[50],
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BEACON MAIS PRÓXIMO',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green[800]),
              ),
              const SizedBox(height: 8),
              Text(beacon.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.signal_cellular_alt, size: 16),
                  const SizedBox(width: 4),
                  Text('RSSI: ${beacon.rssi} dBm'),
                  const SizedBox(width: 16),
                  const Icon(Icons.straighten, size: 16),
                  const SizedBox(width: 4),
                  Text('~${beacon.distance.toStringAsFixed(1)}m'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBeaconList(BLEService bleService) {
    return ListView.builder(
      itemCount: bleService.discoveredBeacons.length,
      itemBuilder: (context, index) {
        final beacon = bleService.discoveredBeacons[index];
        final isClosest = beacon.id == bleService.closestBeacon?.id;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: isClosest ? Colors.green[100] : null,
          child: ListTile(
            leading: Icon(Icons.bluetooth, color: isClosest ? Colors.green : Colors.blue),
            title: Text(beacon.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${beacon.id.substring(0, 8)}...'),
                Text('RSSI: ${beacon.rssi} dBm'),
                Text('Distância: ~${beacon.distance.toStringAsFixed(2)} m'),
                Text('Visto: ${_formatTime(beacon.lastSeen)}'),
              ],
            ),
            trailing: isClosest ? const Icon(Icons.star, color: Colors.green) : null,
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _buildStatusBar(BLEService bleService) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Beacons encontrados: ${bleService.discoveredBeacons.length}'),
          Text(
            bleService.isScanning ? 'Escaneando...' : 'Parado',
            style: TextStyle(
              color: bleService.isScanning ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}
