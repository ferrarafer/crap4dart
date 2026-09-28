import 'dart:convert';
import 'dart:io';

import 'package:crap4dart/src/gates/baseline.dart';
import 'package:crap4dart/src/gates/gate.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('baseline_file'));
  tearDown(() => root.deleteSync(recursive: true));

  List<GateViolation> fresh(Baseline baseline, List<GateViolation> now) =>
      applyBaseline('loc', GateResult.fail('loc', now), baseline).violations;

  test('version 1 files load, ignoring line and measure', () {
    File(p.join(root.path, baselineFileName)).writeAsStringSync(jsonEncode({
      'version': 1,
      'violations': [
        {'gate': 'loc', 'file': 'lib/a.dart', 'line': 3, 'message': 'x'},
      ],
    }));
    final v1 = Baseline.load(root.path);
    const now =
        GateViolation(file: 'lib/a.dart', line: 7, message: 'x', measure: 1000);
    expect(fresh(v1, [now]), isEmpty);
  });

  test('writes version 2 without line numbers', () {
    const violation = GateViolation(
      file: 'lib/a.dart',
      line: 5,
      message: '900 lines > max 800',
      measure: 900,
    );
    writeBaseline(root.path, [
      GateResult.fail('loc', [violation]),
    ]);
    final json =
        jsonDecode(File(p.join(root.path, baselineFileName)).readAsStringSync())
            as Map;
    expect(json['version'], 2);
    expect((json['violations'] as List).single, {
      'gate': 'loc',
      'file': 'lib/a.dart',
      'message': '900 lines > max 800',
      'measure': 900
    });
  });

  test('a malformed file is an empty baseline', () {
    File(p.join(root.path, baselineFileName)).writeAsStringSync('{nope');
    expect(Baseline.load(root.path).entries, isEmpty);
  });
}
