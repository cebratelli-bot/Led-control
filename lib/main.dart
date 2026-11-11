import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'magic_home.dart';

void main() => runApp(const LedApp());

class LedApp extends StatelessWidget {
  const LedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LED Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C4DFF),
      ),
      home: const HomePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Tela inicial: lista de fitas
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _prefsKey = 'devices_v1';
  final List<MagicHomeDevice> _devices = [];
  final Map<String, LedState?> _states = {};
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final d in _devices) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      setState(() {
        _devices.addAll(list.map(MagicHomeDevice.fromJson));
      });
    }
    if (_devices.isEmpty) {
      _scan();
    } else {
      _refreshAll();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_devices.map((d) => d.toJson()).toList()));
  }

  Future<void> _refreshAll() async {
    await Future.wait(_devices.map((d) async {
      LedState? s;
      try {
        s = await d.refresh();
      } catch (_) {
        s = null;
      }
      if (mounted) setState(() => _states[d.ip] = s);
    }));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final found = await discoverDevices();
      var added = 0;
      for (final f in found) {
        if (_devices.any((d) => d.ip == f.ip)) continue;
        _devices.add(MagicHomeDevice(
          ip: f.ip,
          mac: f.mac,
          model: f.model,
          name: 'Fita ${_devices.length + 1}',
        ));
        added++;
      }
      await _save();
      if (!mounted) return;
      _toast(found.isEmpty
          ? 'Nenhuma fita encontrada. Confira se o celular está no mesmo Wi-Fi.'
          : added == 0
              ? 'Nenhuma fita nova (${found.length} já salva(s)).'
              : '$added fita(s) nova(s) encontrada(s)!');
      await _refreshAll();
    } catch (e) {
      if (mounted) _toast('Erro na busca: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _addManual() async {
    final ipCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: 'Fita ${_devices.length + 1}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar pelo IP'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ipCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'IP', hintText: '192.168.0.50'),
          ),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Adicionar')),
        ],
      ),
    );
    final ip = ipCtrl.text.trim();
    if (ok != true || ip.isEmpty) return;
    if (_devices.any((d) => d.ip == ip)) {
      _toast('Esse IP já está na lista.');
      return;
    }
    final d = MagicHomeDevice(
        ip: ip, name: nameCtrl.text.trim().isEmpty ? ip : nameCtrl.text.trim());
    setState(() => _devices.add(d));
    await _save();
    _refreshAll();
  }

  Future<void> _editDevice(MagicHomeDevice d) async {
    final nameCtrl = TextEditingController(text: d.name);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar fita'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Text('Remover', style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (action == 'save') {
      setState(() => d.name = nameCtrl.text.trim().isEmpty ? d.ip : nameCtrl.text.trim());
    } else if (action == 'remove') {
      d.dispose();
      setState(() {
        _devices.remove(d);
        _states.remove(d.ip);
      });
    }
    await _save();
  }

  Future<void> _powerAll(bool on) async {
    final results = await Future.wait(_devices.map((d) async {
      try {
        await d.setPower(on);
        return true;
      } catch (_) {
        return false;
      }
    }));
    final fails = results.where((r) => !r).length;
    if (fails > 0) _toast('$fails fita(s) não responderam.');
    _refreshAll();
  }

  Future<void> _openControl(List<MagicHomeDevice> targets, String title) async {
    final first = _states[targets.first.ip];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ControlPage(
            devices: targets, title: title, initial: first),
      ),
    );
    _refreshAll();
  }

  Future<void> _togglePower(MagicHomeDevice d, bool on) async {
    try {
      await d.setPower(on);
      final s = _states[d.ip];
      setState(() =>
          _states[d.ip] = LedState(on, s?.r ?? 255, s?.g ?? 255, s?.b ?? 255, s?.model ?? 0));
    } catch (_) {
      _toast('${d.name} não respondeu.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas fitas'),
        actions: [
          IconButton(
            tooltip: 'Buscar no Wi-Fi',
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_find),
          ),
          IconButton(
            tooltip: 'Adicionar pelo IP',
            onPressed: _addManual,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_devices.isEmpty && !_scanning)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Column(children: [
                  const Icon(Icons.lightbulb_outline, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Nenhuma fita ainda.\nConecte o celular no mesmo Wi-Fi das fitas e toque em buscar.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.wifi_find),
                      label: const Text('Buscar fitas')),
                ]),
              ),
            if (_devices.length > 1)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.select_all),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text('Todas as fitas',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    IconButton.filledTonal(
                        tooltip: 'Desligar todas',
                        onPressed: () => _powerAll(false),
                        icon: const Icon(Icons.power_settings_new)),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        tooltip: 'Ligar todas',
                        onPressed: () => _powerAll(true),
                        icon: const Icon(Icons.lightbulb)),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                        tooltip: 'Cor de todas',
                        onPressed: () =>
                            _openControl(List.of(_devices), 'Todas as fitas'),
                        icon: const Icon(Icons.palette)),
                  ]),
                ),
              ),
            for (final d in _devices) _deviceTile(d),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(MagicHomeDevice d) {
    final s = _states[d.ip];
    final offline = _states.containsKey(d.ip) && s == null;
    final color = s == null
        ? Colors.grey
        : Color.fromARGB(255, s.r, s.g, s.b);
    return Card(
      child: ListTile(
        onTap: () => _openControl([d], d.name),
        onLongPress: () => _editDevice(d),
        leading: CircleAvatar(
          backgroundColor: s != null && s.on ? color : Colors.black26,
          child: Icon(Icons.lightbulb,
              color: s != null && s.on ? Colors.white : Colors.white38),
        ),
        title: Text(d.name),
        subtitle: Text(offline ? '${d.ip} • sem resposta' : d.ip),
        trailing: Switch(
          value: s?.on ?? false,
          onChanged: offline ? null : (v) => _togglePower(d, v),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tela de controle (uma fita ou várias ao mesmo tempo)
// ---------------------------------------------------------------------------

class ControlPage extends StatefulWidget {
  final List<MagicHomeDevice> devices;
  final String title;
  final LedState? initial;

  const ControlPage(
      {super.key, required this.devices, required this.title, this.initial});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  double _hue = 270, _sat = 1, _val = 1;
  bool _on = true;
  int? _effect;
  double _speed = 60;

  Timer? _throttle;
  bool _pending = false;

  static const _swatches = <double?>[0, 25, 50, 120, 180, 210, 270, 310, null];

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    if (s != null) {
      _on = s.on;
      if (s.r + s.g + s.b > 0) {
        final hsv = rgbToHsv(s.r, s.g, s.b);
        _hue = hsv[0];
        _sat = hsv[1];
        _val = hsv[2].clamp(0.05, 1.0).toDouble();
      }
    }
  }

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  List<int> get _rgb => hsvToRgb(_hue, _sat, _val);

  Future<void> _forAll(Future<void> Function(MagicHomeDevice d) op) async {
    var fails = 0;
    await Future.wait(widget.devices.map((d) async {
      try {
        await op(d);
      } catch (_) {
        fails++;
      }
    }));
    if (fails > 0 && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('$fails fita(s) não responderam.')));
    }
  }

  void _sendColor() {
    final c = _rgb;
    _forAll((d) => d.setColor(c[0], c[1], c[2]));
  }

  /// Envia no máximo ~12 comandos por segundo enquanto o slider se mexe.
  void _colorChanged() {
    setState(() {
      _effect = null;
      _on = true;
    });
    if (_throttle == null) {
      _sendColor();
      _throttle = Timer.periodic(const Duration(milliseconds: 80), (t) {
        if (_pending) {
          _pending = false;
          _sendColor();
        } else {
          t.cancel();
          _throttle = null;
        }
      });
    } else {
      _pending = true;
    }
  }

  void _setPower(bool on) {
    setState(() => _on = on);
    _forAll((d) => d.setPower(on));
  }

  void _setEffect(int code) {
    setState(() {
      _effect = code;
      _on = true;
    });
    _forAll((d) => d.setEffect(code, _speed.round()));
  }

  @override
  Widget build(BuildContext context) {
    final c = _rgb;
    final preview = Color.fromARGB(255, c[0], c[1], c[2]);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: GestureDetector(
              onTap: () => _setPower(!_on),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _on ? preview : Colors.black26,
                  boxShadow: _on
                      ? [
                          BoxShadow(
                              color: Color.fromARGB(150, c[0], c[1], c[2]),
                              blurRadius: 50,
                              spreadRadius: 6)
                        ]
                      : null,
                ),
                child: Icon(Icons.power_settings_new,
                    size: 56, color: _on ? Colors.white : Colors.white38),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(_on ? 'Ligada — toque para desligar' : 'Desligada — toque para ligar')),
          const SizedBox(height: 24),
          _sectionTitle('Cores rápidas'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final h in _swatches)
                GestureDetector(
                  onTap: () {
                    if (h == null) {
                      _sat = 0;
                    } else {
                      _hue = h;
                      _sat = 1;
                    }
                    _colorChanged();
                  },
                  child: Builder(builder: (_) {
                    final sc = h == null
                        ? const [255, 255, 255]
                        : hsvToRgb(h, 1, 1);
                    return CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            Color.fromARGB(255, sc[0], sc[1], sc[2]));
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle('Cor'),
          _gradientSlider(
            colors: [
              for (var h = 0; h <= 360; h += 60)
                () {
                  final x = hsvToRgb(h.toDouble(), 1, 1);
                  return Color.fromARGB(255, x[0], x[1], x[2]);
                }()
            ],
            value: _hue,
            max: 360,
            onChanged: (v) {
              _hue = v;
              _colorChanged();
            },
          ),
          _sectionTitle('Saturação'),
          _gradientSlider(
            colors: [
              Colors.white,
              () {
                final x = hsvToRgb(_hue, 1, 1);
                return Color.fromARGB(255, x[0], x[1], x[2]);
              }()
            ],
            value: _sat,
            max: 1,
            onChanged: (v) {
              _sat = v;
              _colorChanged();
            },
          ),
          _sectionTitle('Brilho'),
          _gradientSlider(
            colors: [Colors.black, preview],
            value: _val,
            min: 0.03,
            max: 1,
            onChanged: (v) {
              _val = v;
              _colorChanged();
            },
          ),
          const SizedBox(height: 24),
          _sectionTitle('Efeitos'),
          Row(children: [
            const Icon(Icons.speed, size: 20),
            Expanded(
              child: Slider(
                value: _speed,
                max: 100,
                label: '${_speed.round()}%',
                divisions: 20,
                onChanged: (v) => setState(() => _speed = v),
                onChangeEnd: (_) {
                  if (_effect != null) _setEffect(_effect!);
                },
              ),
            ),
            SizedBox(width: 44, child: Text('${_speed.round()}%')),
          ]),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in ledEffects)
                ChoiceChip(
                  label: Text(e.name),
                  selected: _effect == e.code,
                  onSelected: (_) => _setEffect(e.code),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _gradientSlider({
    required List<Color> colors,
    required double value,
    required double max,
    double min = 0,
    required ValueChanged<double> onChanged,
  }) {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: LinearGradient(colors: colors),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: const Color(0x33FFFFFF),
              trackHeight: 14,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
