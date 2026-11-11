// Comunicação com controladores Magic Home (protocolo LEDENET) pela rede local.
// - Descoberta: UDP broadcast na porta 48899 ("HF-A11ASSISTHREAD")
// - Comandos: TCP na porta 5577

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Variantes do protocolo. A maioria das fitas RGB usa a de 8 bytes.
enum MhProtocol { original, byte8, byte9 }

/// Modelos que usam a mensagem de cor de 9 bytes.
const Set<int> _nineByteModels = {0x07, 0x0E, 0x1E, 0x25, 0x35};

/// Modelos antigos que usam o protocolo original (sem checksum).
const Set<int> _originalModels = {0x01, 0x02, 0x03};

class LedEffect {
  final int code;
  final String name;
  const LedEffect(this.code, this.name);
}

const List<LedEffect> ledEffects = [
  LedEffect(0x25, 'Arco-íris suave'),
  LedEffect(0x38, 'Arco-íris pulando'),
  LedEffect(0x30, 'Arco-íris piscando'),
  LedEffect(0x26, 'Vermelho respirando'),
  LedEffect(0x27, 'Verde respirando'),
  LedEffect(0x28, 'Azul respirando'),
  LedEffect(0x29, 'Amarelo respirando'),
  LedEffect(0x2A, 'Ciano respirando'),
  LedEffect(0x2B, 'Roxo respirando'),
  LedEffect(0x2C, 'Branco respirando'),
  LedEffect(0x2D, 'Vermelho ↔ Verde'),
  LedEffect(0x2E, 'Vermelho ↔ Azul'),
  LedEffect(0x2F, 'Verde ↔ Azul'),
  LedEffect(0x31, 'Vermelho piscando'),
  LedEffect(0x32, 'Verde piscando'),
  LedEffect(0x33, 'Azul piscando'),
  LedEffect(0x34, 'Amarelo piscando'),
  LedEffect(0x35, 'Ciano piscando'),
  LedEffect(0x36, 'Roxo piscando'),
  LedEffect(0x37, 'Branco piscando'),
];

/// Funções puras que montam os bytes de cada comando (testáveis sem rede).
class MhCommands {
  static Uint8List withChecksum(List<int> body) {
    var sum = 0;
    for (final b in body) {
      sum += b;
    }
    return Uint8List.fromList([...body, sum & 0xFF]);
  }

  static Uint8List power(MhProtocol p, bool on) {
    final s = on ? 0x23 : 0x24;
    if (p == MhProtocol.original) return Uint8List.fromList([0xCC, s, 0x33]);
    return withChecksum([0x71, s, 0x0F]);
  }

  static Uint8List color(MhProtocol p, int r, int g, int b) {
    r = r.clamp(0, 255);
    g = g.clamp(0, 255);
    b = b.clamp(0, 255);
    return switch (p) {
      MhProtocol.original => Uint8List.fromList([0x56, r, g, b, 0xAA]),
      MhProtocol.byte8 => withChecksum([0x31, r, g, b, 0x00, 0xF0, 0x0F]),
      MhProtocol.byte9 =>
        withChecksum([0x31, r, g, b, 0x00, 0x00, 0xF0, 0x0F]),
    };
  }

  /// speed: 0 (lento) a 100 (rápido). O aparelho usa "delay" de 1 a 31.
  static int speedToDelay(int speed) {
    final s = speed.clamp(0, 100);
    return ((100 - s) * 30) ~/ 100 + 1;
  }

  static Uint8List effect(MhProtocol p, int code, int speed) {
    final d = speedToDelay(speed);
    if (p == MhProtocol.original) {
      return Uint8List.fromList([0xBB, code, d, 0x44]);
    }
    return withChecksum([0x61, code, d, 0x0F]);
  }

  static Uint8List query(MhProtocol p) {
    if (p == MhProtocol.original) return Uint8List.fromList([0xEF, 0x01, 0x77]);
    return withChecksum([0x81, 0x8A, 0x8B]);
  }
}

class LedState {
  final bool on;
  final int r, g, b;
  final int model;
  const LedState(this.on, this.r, this.g, this.b, this.model);
}

class MagicHomeDevice {
  final String ip;
  String name;
  final String mac;
  final String model;
  MhProtocol? protocol;

  Socket? _socket;
  final List<int> _buffer = [];
  Future<void>? _connecting;
  Future<void> _queue = Future.value();

  MagicHomeDevice({
    required this.ip,
    required this.name,
    this.mac = '',
    this.model = '',
  });

  Map<String, dynamic> toJson() =>
      {'ip': ip, 'name': name, 'mac': mac, 'model': model};

  factory MagicHomeDevice.fromJson(Map<String, dynamic> j) => MagicHomeDevice(
        ip: j['ip'] as String,
        name: (j['name'] as String?) ?? j['ip'] as String,
        mac: (j['mac'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
      );

  Future<void> _ensureConnected() async {
    if (_socket != null) return;
    _connecting ??= () async {
      try {
        final s = await Socket.connect(ip, 5577,
            timeout: const Duration(seconds: 3));
        s.setOption(SocketOption.tcpNoDelay, true);
        s.listen(
          (data) => _buffer.addAll(data),
          onError: (_) => _drop(),
          onDone: _drop,
          cancelOnError: true,
        );
        _socket = s;
      } finally {
        _connecting = null;
      }
    }();
    await _connecting;
  }

  void _drop() {
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void dispose() => _drop();

  /// Executa as operações em fila, uma de cada vez.
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _write(Uint8List bytes) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _ensureConnected();
        _socket!.add(bytes);
        await _socket!.flush();
        return;
      } catch (_) {
        _drop();
        if (attempt == 1) rethrow;
      }
    }
  }

  /// Envia uma consulta e espera uma resposta que começa com [head].
  Future<Uint8List?> _request(Uint8List bytes, int head, int length) async {
    _buffer.clear();
    await _write(bytes);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      final i = _buffer.indexOf(head);
      if (i >= 0 && _buffer.length - i >= length) {
        return Uint8List.fromList(_buffer.sublist(i, i + length));
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
    return null;
  }

  /// Descobre qual variante do protocolo o controlador usa e lê o estado.
  Future<LedState?> refresh() => _serial(() async {
        final r = await _request(MhCommands.query(MhProtocol.byte8), 0x81, 14);
        if (r != null) {
          final m = r[1];
          protocol ??= _nineByteModels.contains(m)
              ? MhProtocol.byte9
              : _originalModels.contains(m)
                  ? MhProtocol.original
                  : MhProtocol.byte8;
          return LedState(r[2] == 0x23, r[6], r[7], r[8], m);
        }
        final o = await _request(MhCommands.query(MhProtocol.original), 0x66, 11);
        if (o != null) {
          protocol ??= MhProtocol.original;
          return LedState(o[2] == 0x23, o[6], o[7], o[8], o[1]);
        }
        protocol ??= MhProtocol.byte8;
        return null;
      });

  Future<MhProtocol> _proto() async {
    if (protocol == null) {
      try {
        await refresh();
      } catch (_) {}
    }
    return protocol ?? MhProtocol.byte8;
  }

  Future<void> setPower(bool on) async {
    final p = await _proto();
    await _serial(() => _write(MhCommands.power(p, on)));
  }

  Future<void> setColor(int r, int g, int b) async {
    final p = await _proto();
    await _serial(() => _write(MhCommands.color(p, r, g, b)));
  }

  Future<void> setEffect(int code, int speed) async {
    final p = await _proto();
    await _serial(() => _write(MhCommands.effect(p, code, speed)));
  }
}

class DiscoveredDevice {
  final String ip, mac, model;
  DiscoveredDevice(this.ip, this.mac, this.model);
}

/// Procura controladores Magic Home na rede Wi-Fi atual.
Future<List<DiscoveredDevice>> discoverDevices(
    {Duration timeout = const Duration(seconds: 3)}) async {
  RawDatagramSocket socket;
  try {
    // Controladores antigos só respondem se a porta de origem for 48899.
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 48899);
  } catch (_) {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }
  socket.broadcastEnabled = true;

  final found = <String, DiscoveredDevice>{};
  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    final text = utf8.decode(dg.data, allowMalformed: true).trim();
    final parts = text.split(',');
    if (parts.length >= 3 && InternetAddress.tryParse(parts[0]) != null) {
      found[parts[0]] = DiscoveredDevice(parts[0], parts[1], parts[2]);
    }
  });

  final msg = utf8.encode('HF-A11ASSISTHREAD');
  final targets = [InternetAddress('255.255.255.255')];
  // Também tenta o broadcast da sub-rede (ex.: 192.168.0.255).
  try {
    for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4)) {
      for (final a in iface.addresses) {
        final o = a.rawAddress;
        if (o[0] == 127) continue;
        targets.add(InternetAddress('${o[0]}.${o[1]}.${o[2]}.255'));
      }
    }
  } catch (_) {}

  for (var i = 0; i < 3; i++) {
    for (final t in targets) {
      try {
        socket.send(msg, t, 48899);
      } catch (_) {}
    }
    await Future.delayed(timeout ~/ 3);
  }

  await sub.cancel();
  socket.close();
  return found.values.toList();
}

/// Converte HSV (h 0-360, s e v 0-1) para RGB 0-255.
List<int> hsvToRgb(double h, double s, double v) {
  final c = v * s;
  final hp = (h % 360) / 60.0;
  final x = c * (1 - ((hp % 2) - 1).abs());
  double r = 0, g = 0, b = 0;
  if (hp < 1) {
    r = c; g = x;
  } else if (hp < 2) {
    r = x; g = c;
  } else if (hp < 3) {
    g = c; b = x;
  } else if (hp < 4) {
    g = x; b = c;
  } else if (hp < 5) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  final m = v - c;
  int to255(double d) => ((d + m) * 255).round().clamp(0, 255);
  return [to255(r), to255(g), to255(b)];
}

/// Converte RGB 0-255 para HSV [h 0-360, s 0-1, v 0-1].
List<double> rgbToHsv(int r, int g, int b) {
  final rf = r / 255, gf = g / 255, bf = b / 255;
  final mx = [rf, gf, bf].reduce((a, c) => a > c ? a : c);
  final mn = [rf, gf, bf].reduce((a, c) => a < c ? a : c);
  final d = mx - mn;
  double h = 0;
  if (d > 0) {
    if (mx == rf) {
      h = 60 * (((gf - bf) / d) % 6);
    } else if (mx == gf) {
      h = 60 * (((bf - rf) / d) + 2);
    } else {
      h = 60 * (((rf - gf) / d) + 4);
    }
  }
  if (h < 0) h += 360;
  return [h, mx == 0 ? 0.0 : d / mx, mx];
}
