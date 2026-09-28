import 'dart:convert';
import 'dart:io';

import 'package:crap4dart/src/gates/baseline.dart';
import 'package:crap4dart/src/gates/gate.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

GateViolation _loc(int lines) => GateViolation(
      file: 'lib/a.dart',
      message: '$lines lines > max 400',
      measure: lines,
    );

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('tighten_gates'));
  tearDown(() => root.deleteSync(recursive: true));

  void save(List<GateResult> results) => writeBaseline(root.path, results);

  List<Map<String, dynamic>> stored() {
    final json = jsonDecode(
      File(p.join(root.path, baselineFileName)).readAsStringSync(),
    ) as Map<String, dynamic>;
    return (json['violations'] as List).cast<Map<String, dynamic>>();
  }

  test('keeps entries of gates that did not run', () {
    const doc = GateViolation(file: 'lib/a.dart', message: 'missing doc');
    save([
      GateResult.fail('loc', [_loc(900)]),
      GateResult.fail('public_docs', [doc]),
      GateResult.fail('complexity', [_loc(20)]),
    ]);
    final stats = tightenBaseline(root.path, [
      GateResult.fail('loc', const []),
      GateResult.skip('complexity', 'disabled in config'),
    ])!;
    expect((stats.kept, stats.removed), (2, 1));
    expect(stored().map((e) => e['gate']), ['public_docs', 'complexity']);
  });

  test('returns null without a baseline file', () {
    expect(tightenBaseline(root.path, const []), isNull);
  });
}
