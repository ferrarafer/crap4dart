import 'dart:convert';
import 'dart:io';

import 'package:crap4dart/src/gates/baseline.dart';
import 'package:crap4dart/src/gates/gate.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

GateViolation _loc(int lines, {String file = 'lib/a.dart'}) => GateViolation(
      file: file,
      message: '$lines lines > max 400',
      measure: lines,
    );

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('baseline_tighten'));
  tearDown(() => root.deleteSync(recursive: true));

  void save(List<GateResult> results) => writeBaseline(root.path, results);

  List<Map<String, dynamic>> stored() {
    final json = jsonDecode(
      File(p.join(root.path, baselineFileName)).readAsStringSync(),
    ) as Map<String, dynamic>;
    return (json['violations'] as List).cast<Map<String, dynamic>>();
  }

  TightenStats tighten(List<GateViolation> now) =>
      tightenBaseline(root.path, [GateResult.fail('loc', now)])!;

  test('lowers the ceiling of a shrunk violation', () {
    save([
      GateResult.fail('loc', [_loc(900)])
    ]);
    final stats = tighten([_loc(850)]);
    expect((stats.kept, stats.lowered, stats.removed), (1, 1, 0));
    expect(stored().single['measure'], 850);
    // Growing back to the old size is now a new violation.
    final grownBack = Baseline.load(root.path).uncovered('loc', [_loc(900)]);
    expect(grownBack, hasLength(1));
  });

  test('drops entries whose violation is fixed', () {
    save([
      GateResult.fail('loc', [_loc(900), _loc(500, file: 'lib/b.dart')]),
    ]);
    final stats = tighten([_loc(900)]);
    expect((stats.kept, stats.removed), (1, 1));
    expect(stored().single['file'], 'lib/a.dart');
  });

  test('never adds new violations', () {
    save([
      GateResult.fail('loc', [_loc(900)])
    ]);
    final stats = tighten([_loc(900), _loc(700, file: 'lib/new.dart')]);
    expect((stats.kept, stats.notAdded), (1, 1));
    expect(stored().map((e) => e['file']), ['lib/a.dart']);
  });

  test('keeps the old ceiling of a grown violation', () {
    save([
      GateResult.fail('loc', [_loc(900)])
    ]);
    final stats = tighten([_loc(950)]);
    expect((stats.kept, stats.removed, stats.notAdded), (1, 0, 1));
    expect(stored().single['measure'], 900);
    final back = Baseline.load(root.path).uncovered('loc', [_loc(900)]);
    expect(back, isEmpty, reason: 'shrinking back must be covered again');
  });

  test('a no-op tighten leaves the file byte-identical', () {
    // Same key (file + message shape), ascending measures: matching sorts
    // largest first, the file must keep violation order.
    final now = [_loc(500), _loc(900), _loc(700, file: 'lib/c.dart')];
    save([GateResult.fail('loc', now)]);
    final file = File(p.join(root.path, baselineFileName));
    final before = file.readAsStringSync();
    tighten(now);
    expect(file.readAsStringSync(), before);
  });
}
