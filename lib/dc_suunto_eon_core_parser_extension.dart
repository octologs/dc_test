import 'dart:typed_data';

import './dc_suunto_eon_core_parser.dart';

extension SuuntoEonCoreCommands on SuuntoHdlcParser {
  /// Re-sends the INIT handshake (record type 0x0002), which yields the 0×30-byte
  /// version block that your parser picks up as `deviceInfo`.
  Future<void> requestDeviceInfo(
    Future<void> Function(Uint8List data) writeFn,
  ) async {
    // First 20-byte chunk (start flag, header, payload, first 3 CRC bytes)
    final chunk1 = <int>[
      0x7E, // HDLC start flag
      0x00, 0x00, // CMD_INIT = 0x0000
      0x01, 0x00, 0x00, 0x00, // INIT_MAGIC
      0x00, 0x00, // INIT_SEQ
      0x04, 0x00, 0x00, 0x00, // payload length = 4
      0x02, 0x00, 0x2A, 0x00, // record type = 0x0002, record ID = 0x002A
      0x7A, 0xA0, 0x9C, // first 3 bytes of CRC-32 (little-endian)
    ];

    // Second chunk (final CRC byte + end flag)
    final chunk2 = <int>[
      0x30, // last CRC-32 byte
      0x7E, // HDLC end flag
    ];

    await writeFn(
      Uint8List.fromList(chunk1),
    ); // Write first packet :contentReference[oaicite:2]{index=2}
    await writeFn(Uint8List.fromList(chunk2)); // Write second packet
  }
}
