@Timeout.factor(2)
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_test_utils.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = createCliTestProject());
  tearDown(() => tempDir.deleteSync(recursive: true));

  group('crap4dart global exclude', () {
    test('excluded files are skipped in check', () async {
      writeCleanProject(tempDir);
      Directory(p.join(tempDir.path, 'lib', 'gen')).createSync();
      File(p.join(tempDir.path, 'lib', 'gen', 'bad.dart'))
          .writeAsStringSync('void undocumented() {}\n');
      // Without the exclude, public_docs would fail on gen/bad.dart.
      final withoutExclude = await runCliInProcess(tempDir, ['check']);
      expect(withoutExclude.exitCode, 2);

      File(p.join(tempDir.path, 'crap4dart.yaml')).writeAsStringSync('''
coverage:
  required: false
  run_tests: false
exclude:
  - 'lib/gen/**'
''');
      final result = await runCliInProcess(tempDir, ['check']);
      expect(result.exitCode, 0);
      expect(result.stdout, isNot(contains('gen/bad.dart')));
    });

    test('imports from excluded files still count for unused_files', () async {
      writeCleanProject(tempDir);
      File(p.join(tempDir.path, 'lib', 'src', 'screen.dart'))
          .writeAsStringSync('/// A screen.\nvoid screen() {}\n');
      // Generated code (e.g. a router) is the only importer of screen.dart.
      Directory(p.join(tempDir.path, 'lib', 'gen')).createSync();
      File(p.join(tempDir.path, 'lib', 'gen', 'router.dart'))
          .writeAsStringSync("import '../src/screen.dart';\n\n"
              '/// Routes.\nvoid route() => screen();\n');
      File(p.join(tempDir.path, 'crap4dart.yaml')).writeAsStringSync('''
coverage:
  required: false
  run_tests: false
exclude:
  - 'lib/gen/**'
''');
      final result =
          await runCliInProcess(tempDir, ['check', '--only', 'unused_files']);
      expect(result.stdout, isNot(contains('screen.dart')));
      expect(result.stdout, isNot(contains('router.dart')));
      expect(result.exitCode, 0);
    });

    test('excluded files are skipped in analyze', () async {
      writeMiniProject(tempDir, lcov: fullCoverageLcov);
      Directory(p.join(tempDir.path, 'lib', 'gen')).createSync();
      File(p.join(tempDir.path, 'lib', 'gen', 'extra.dart'))
          .writeAsStringSync('int extra() => 1;\n');
      File(p.join(tempDir.path, 'crap4dart.yaml')).writeAsStringSync('''
exclude:
  - 'lib/gen/**'
''');
      final result = await runCliInProcess(tempDir, ['analyze']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('risky'));
      expect(result.stdout, isNot(contains('extra')));
    });
  });
}
