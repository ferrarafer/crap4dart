import 'dart:io';

import 'package:crap4dart/src/gates/baseline.dart';
import 'package:crap4dart/src/gates/gate.dart';
import 'package:test/test.dart';

GateViolation _loc(int lines, {int? line, String file = 'lib/a.dart'}) =>
    GateViolation(
      file: file,
      line: line,
      message: '$lines lines > max 800',
      measure: lines,
    );

GateResult _fail(List<GateViolation> violations) =>
    GateResult.fail('loc', violations);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('baseline_test'));
  tearDown(() => root.deleteSync(recursive: true));

  Baseline saved(List<GateViolation> violations) {
    writeBaseline(root.path, [_fail(violations)]);
    return Baseline.load(root.path);
  }

  List<GateViolation> fresh(Baseline baseline, List<GateViolation> now) =>
      applyBaseline('loc', _fail(now), baseline).violations;

  test('shifted lines stay covered', () {
    final baseline = saved([_loc(900, line: 10)]);
    final result = applyBaseline('loc', _fail([_loc(900, line: 42)]), baseline);
    expect(result.passed, isTrue);
  });

  test('a shrinking measure stays covered', () {
    expect(fresh(saved([_loc(900)]), [_loc(850)]), isEmpty);
  });

  test('a growing measure is a fresh violation', () {
    final grown = _loc(950);
    expect(fresh(saved([_loc(900)]), [grown]), [grown]);
  });

  test('covers only as many violations as were stored', () {
    const stored = GateViolation(file: 'lib/a.dart', message: 'missing doc');
    final now = [
      for (var i = 0; i < 3; i++)
        GateViolation(file: 'lib/a.dart', line: i, message: 'missing doc'),
    ];
    expect(fresh(saved([stored, stored]), now), hasLength(1));
  });

  test('matches the largest measures first', () {
    final baseline = saved([_loc(900), _loc(820)]);
    final small = _loc(810);
    final big = _loc(890);
    expect(fresh(baseline, [small, big]), isEmpty);
    final tooBig = _loc(910);
    expect(fresh(baseline, [small, tooBig]), [tooBig]);
  });

  test('other files and gates are not covered', () {
    final baseline = saved([_loc(900)]);
    expect(fresh(baseline, [_loc(900, file: 'lib/b.dart')]), hasLength(1));
    final other = applyBaseline(
        'complexity', GateResult.fail('complexity', [_loc(900)]), baseline);
    expect(other.passed, isFalse);
  });

  test('applies to severity: warning gates', () {
    final baseline = saved([_loc(900)]);
    final covered =
        applyBaseline('loc', GateResult.warn('loc', [_loc(900)]), baseline);
    expect(covered.warning, isFalse);
    expect(covered.violations, isEmpty);
    final grown = _loc(950);
    final still =
        applyBaseline('loc', GateResult.warn('loc', [grown]), baseline);
    expect(still.warning, isTrue);
    expect(still.passed, isTrue);
  });
}
