import 'dart:async';
import 'dart:typed_data';

/// Stateful decoder for Suunto EON-series dive computers.
///
/// • Handles **HDLC/PPP** framing (0x7E flags, 0x7D 0x20 escaping).
/// • Verifies **CRC-32** or **CRC-16/KERMIT** depending on command.
/// • Reassembles multi-fragment replies.
/// • Emits
///   • `deviceInfo`  → 0x30-byte **version** block (prod/serial/fw/hw)
class SuuntoHdlcParser {
  // ────────────────────────── public API ──────────────────────────────
  final _devInfo = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get deviceInfo => _devInfo.stream;

  void dispose() {
    _devInfo.close();
  }

  /// Feed *raw* BLE notification chunks.
  void addChunk(Uint8List chunk) {
    for (final b in chunk) {
      if (b == _flag) {
        if (_inFrame && _frame.isNotEmpty) _processFrame();
        _inFrame = true;
      } else if (_inFrame) {
        _frame.add(b);
      }
    }
  }

  // ───────────────────────── private implementation ───────────────────
  static const int _flag = 0x7E; // HDLC flag
  final _frame = <int>[]; // current HDLC frame being collected
  bool _inFrame = false;

  // ────────────── HDLC frame handling and CRC verification ────────────
  void _processFrame() {
    final unescaped = _hdlcUnescape(Uint8List.fromList(_frame));
    _frame.clear();
    if (unescaped.length < 4) return; // need ≥ payload + CRC

    // choose CRC width by command family
    final cmd = unescaped[2] | (unescaped[3] << 8);
    final isInit = cmd == 0x0002; // CMD_INIT → always CRC-32
    final crcLen = isInit ? 4 : 2;
    if (unescaped.length <= crcLen) return;

    final trailer = unescaped.length - crcLen;
    final payload = unescaped.sublist(0, trailer);
    final sentCrc =
        isInit
            ? _bytesToUint32LE(unescaped, trailer)
            : (unescaped[trailer] | (unescaped[trailer + 1] << 8));

    final calcCrc = isInit ? _crc32(payload) : _crc16Kermit(payload);
    if (sentCrc != calcCrc) {
      print('CRC error – fragment dropped');
      return;
    }

    // header layout: seq | flags | cmd(LE) | len(LE) | …data…
    final seq = payload[0];
    final data = payload.sublist(6);

    // first INIT reply carries 0×30-byte version block
    if (isInit && seq == 0 && data.length >= 0x30) {
      _emitDeviceInfo(data.sublist(0, 0x30));
    }
  }

  // ───────────── HDLC byte de-stuffing (RFC 1662 §4.3) ────────────────
  Uint8List _hdlcUnescape(Uint8List frame) {
    final out = <int>[];
    bool esc = false;
    for (final b in frame) {
      if (esc) {
        out.add(b ^ 0x20);
        esc = false;
      } else if (b == 0x7D) {
        esc = true;
      } else {
        out.add(b);
      }
    }
    return Uint8List.fromList(out);
  }

  // ───────────────────────────── CRC helpers ──────────────────────────
  int _crc32(Uint8List bytes) {
    const poly = 0xEDB88320;
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (var i = 0; i < 8; ++i) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ poly : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  int _crc16Kermit(Uint8List data) {
    var crc = 0x0000;
    for (final byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; ++i) {
        crc = (crc & 0x0001) != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1;
      }
    }
    return crc & 0xFFFF;
  }

  // ─────────────────────── version-block decoding ─────────────────────
  static const _vbProd = 6; // product (16 B)
  static const _vbSer = 22; // serial  (12 B)
  static const _vbFw = 38; // firmware (4 B)
  static const _vbHw = 42; // hardware (4 B)

  void _emitDeviceInfo(Uint8List v) {
    final prod =
        String.fromCharCodes(
          v.sublist(_vbProd, _vbSer),
        ).replaceAll('\x00', '').trim();
    final ser =
        String.fromCharCodes(
          v.sublist(_vbSer, _vbFw),
        ).replaceAll('\x00', '').trim();

    String quad(Uint8List b) => '${b[0]}.${b[1]}.${b[2]}.${b[3]}';
    final fw = quad(v.sublist(_vbFw, _vbFw + 4));
    final hw = quad(v.sublist(_vbHw, _vbHw + 4));

    _devInfo.add({
      'product': prod,
      'serial': ser,
      'firmware': fw,
      'hardware': hw,
    });
  }

  // ──────────────────────────── helpers ───────────────────────────────
  static int _bytesToUint32LE(Uint8List buf, int off) =>
      buf[off] |
      (buf[off + 1] << 8) |
      (buf[off + 2] << 16) |
      (buf[off + 3] << 24);
}
