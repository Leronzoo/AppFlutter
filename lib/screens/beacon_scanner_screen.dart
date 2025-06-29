import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../models/beacon_device.dart';
import 'dart:convert';

class BeaconScannerScreen extends StatefulWidget {
  const BeaconScannerScreen({Key? key}) : super(key: key);

  @override
  _BeaconScannerScreenState createState() => _BeaconScannerScreenState();
}

class _BeaconScannerScreenState extends State<BeaconScannerScreen> {
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
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _connectAndReadData(beacon.id),
                child: const Text('Conectar e Ler Dados'),
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
          onTap: () => _connectAndReadData(beacon.id),
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

  Future<void> _connectAndReadData(String deviceId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Conectando ao beacon...'),
          ],
        ),
      ),
    );

    final data = await context.read<BLEService>().connectAndReadData(deviceId);
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dados do Beacon'),
        content: SingleChildScrollView(
          child: Text(
            data != null ? JsonEncoder.withIndent('  ').convert(data) : 'Falha ao ler dados do beacon',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
