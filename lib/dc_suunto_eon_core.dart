import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import './dc_suunto_eon_core_parser.dart';
import './dc_suunto_eon_core_parser_extension.dart';

class DcSuuntoEonCore {
  StreamSubscription? _subscription;

  Future<void> dispose() async {
    if (_subscription != null) {
      _subscription!.cancel();
    }
  }

  Future<void> download(BluetoothDevice device) async {
    // await device.requestMtu(512); //on iOS automatic, can only be set manually for Android

    // 1. Discover services
    List<BluetoothService> services = await device.discoverServices();

    // 2. Select Suunto serial service
    final suuntoService = services.firstWhere(
      (s) => s.uuid == Guid('98AE7120-E62E-11E3-BADD-0002A5D5C51B'),
      orElse: () => throw Exception('Suunto service not found'),
    );
    print('Suunto service found: ${suuntoService.uuid}');

    // 3. Find write & notify characteristics
    final writeChar = suuntoService.characteristics.firstWhere(
      (c) => c.uuid == Guid('C6339440-E62E-11E3-A5B3-0002A5D5C51B'),
    );
    final notifyChar = suuntoService.characteristics.firstWhere(
      (c) => c.uuid == Guid('D0FD6B80-E62E-11E3-A2E9-0002A5D5C51B'),
    );
    print(
      'Write & notify characteristics found: ${writeChar.uuid}, ${notifyChar.uuid}',
    );

    final parser = SuuntoHdlcParser();

    // 1. Listen for parsed events:
    parser.deviceInfo.listen((info) => print('Device Info ➜ $info'));

    // 2. Enable notifications
    await notifyChar.setNotifyValue(true);
    _subscription = notifyChar.onValueReceived.listen(
      (b) => parser.addChunk(Uint8List.fromList(b)),
    );

    // 3. INIT handshake (you’ve already verified this works):
    await parser.requestDeviceInfo(
      (data) => writeChar.write(data, withoutResponse: true),
    );
  }
}
