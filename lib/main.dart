import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import './bluetooth_provider.dart';
import './dc_suunto_eon_core.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => BluetoothProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<void> _scanForDevices;

  final DcSuuntoEonCore _dcSuuntoEonCore = DcSuuntoEonCore();

  @override
  void initState() {
    _scanForDevices =
        Provider.of<BluetoothProvider>(context, listen: false).scanForDevices();

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Suunto EON Core')),
        body: _example(),
      ),
    );
  }

  _example() {
    return FutureBuilder(
      future: Future.wait([_scanForDevices]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else {
          if (snapshot.error != null) {
            return const Center(child: Text('Something went wrong!'));
          } else {
            return Consumer<BluetoothProvider>(
              builder: (context, bluetoothProvider, child) {
                return RefreshIndicator(
                  onRefresh: bluetoothProvider.scanForDevices,
                  child: ListView(
                    children: [
                      ...bluetoothProvider.systemDevices.map(
                        (device) => DiveComputerTile(
                          diveComputerName: device.platformName,
                          isNewDC: false,
                          onPressed: () async {
                            if (!FlutterBluePlus.connectedDevices.contains(
                              device,
                            )) {
                              device.connectionState.listen((
                                BluetoothConnectionState state,
                              ) {
                                print('Connection state: $state');
                              });

                              await device.connect();
                            }

                            await _dcSuuntoEonCore.download(device);
                          },
                        ),
                      ),
                      ...bluetoothProvider.scanResults.map(
                        (device) => DiveComputerTile(
                          diveComputerName: device.device.platformName,
                          isNewDC: true,
                          onPressed: () async {
                            if (!FlutterBluePlus.connectedDevices.contains(
                              device.device,
                            )) {
                              device.device.connectionState.listen((
                                BluetoothConnectionState state,
                              ) {
                                print('Connection state: $state');
                              });

                              await device.device.connect();
                            }

                            await _dcSuuntoEonCore.download(device.device);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }
        }
      },
    );
  }
}

class DiveComputerTile extends StatelessWidget {
  final String diveComputerName;
  final bool isNewDC;
  final Function onPressed;

  const DiveComputerTile({
    super.key,
    required this.diveComputerName,
    required this.isNewDC,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.only(left: 10.0),
          child: Row(
            children: [
              Expanded(child: SizedBox(child: Text(diveComputerName))),
              TextButton(
                onPressed: () => onPressed(),
                child: Text(
                  isNewDC ? 'Connect' : 'Import',
                  style: TextStyle(color: isNewDC ? Colors.red : Colors.green),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
