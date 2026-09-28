import 'dart:io';

import 'package:crap4dart/src/crap/crap_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'crap_test_fixture.dart';

void main() {
  group('CrapAnalyzer unloadedAsUncovered', () {
    late Directory tempDir;

    setUp(() {
      tempDir = createCrapTestProject();
      writeSampleProject(tempDir);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    /// Copies lib/sample.dart to [relative], which has no LCOV entry.
    String unloadedCopy(String relative) {
      final path = p.join(tempDir.path, relative);
      Directory(p.dirname(path)).createSync(recursive: true);
      File(sampleFile(tempDir)).copySync(path);
      return path;
    }

    List<MethodMetrics> analyze(String file, {bool unloaded = true}) =>
        const CrapAnalyzer().analyze(
          [file],
          lcovPath: sampleLcov(tempDir),
          projectRoot: tempDir.path,
          unloadedAsUncovered: unloaded,
        );

    test('scores a file missing under a covered directory as 0%', () {
      final metrics = analyze(unloadedCopy('lib/src/unloaded.dart'));
      final byName = {for (final m in metrics) m.method.methodName: m};
      expect(byName['uncovered']!.coverage, 0.0);
      expect(byName['uncovered']!.crap, 6.0); // CC 2: 2² + 2
      expect(byName['covered']!.coverage, 0.0);
      expect(byName['covered']!.branchCoverage, isNull);
    });

    test('keeps N/A under directories the report does not cover', () {
      final metrics = analyze(unloadedCopy('test/helper.dart'));
      expect(metrics.map((m) => m.coverage), everyElement(isNull));
    });

    test('keeps N/A when the option is off', () {
      final metrics =
          analyze(unloadedCopy('lib/src/unloaded.dart'), unloaded: false);
      expect(metrics.map((m) => m.crap), everyElement(isNull));
    });

    test('keeps N/A without any coverage data', () {
      final metrics = const CrapAnalyzer().analyze(
        [unloadedCopy('lib/src/unloaded.dart')],
        lcovPath: p.join(tempDir.path, 'coverage', 'missing.info'),
        projectRoot: tempDir.path,
        unloadedAsUncovered: true,
      );
      expect(metrics.map((m) => m.coverage), everyElement(isNull));
    });

    test('loaded files keep their measured coverage', () {
      final byName = {
        for (final m in analyze(sampleFile(tempDir))) m.method.methodName: m,
      };
      expect(byName['covered']!.coverage, 1.0);
    });
  });
}
