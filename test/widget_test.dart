// Confere os bytes dos comandos com os valores da biblioteca de referência
// flux_led (Python), que já é usada por muita gente com Magic Home.
import 'package:flutter_test/flutter_test.dart';
import 'package:led_control/magic_home.dart';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('liga/desliga', () {
    expect(hex(MhCommands.power(MhProtocol.byte8, true)), '71230fa3');
    expect(hex(MhCommands.power(MhProtocol.byte8, false)), '71240fa4');
    expect(hex(MhCommands.power(MhProtocol.original, true)), 'cc2333');
  });

  test('cor', () {
    expect(hex(MhCommands.color(MhProtocol.byte8, 255, 0, 0)), '31ff000000f00f2f');
    expect(hex(MhCommands.color(MhProtocol.byte9, 255, 0, 0)), '31ff00000000f00f2f');
    expect(hex(MhCommands.color(MhProtocol.original, 1, 2, 3)), '56010203aa');
  });

  test('efeito e consulta', () {
    expect(hex(MhCommands.effect(MhProtocol.byte8, 0x25, 50)), '6125100fa5');
    expect(hex(MhCommands.effect(MhProtocol.original, 0x25, 50)), 'bb251044');
    expect(hex(MhCommands.query(MhProtocol.byte8)), '818a8b96');
    expect(hex(MhCommands.query(MhProtocol.original)), 'ef0177');
  });

  test('conversão de cor', () {
    expect(hsvToRgb(0, 1, 1), [255, 0, 0]);
    expect(hsvToRgb(120, 1, 1), [0, 255, 0]);
    expect(hsvToRgb(240, 1, 0.5), [0, 0, 128]);
    final hsv = rgbToHsv(0, 0, 255);
    expect(hsv[0], 240);
  });
}
