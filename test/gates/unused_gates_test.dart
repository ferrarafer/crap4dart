import 'package:crap4dart/src/gates/gate_context.dart';
import 'package:crap4dart/src/gates/unused_code_gate.dart';
import 'package:crap4dart/src/gates/unused_files_gate.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'gate_test_utils.dart';

void main() {
  test('unused_code flags unreferenced private declarations', () async {
    final project = createTempProject();
    addTearDown(() => project.deleteSync(recursive: true));
    writeFile(project, 'lib/a.dart', '''
class Public {
  int _usedField = 0;
  int _deadField = 0;

  int used() => _usedField;
}

void _deadFunction() {}
void _aliveFunction() {}

void caller() => _aliveFunction();
''');
    final result = await UnusedCodeGate().run(
      makeContext(project, ['lib/a.dart']),
    );
    expect(result.passed, isFalse);
    final names = result.violations.map((v) => v.message).toList();
    expect(names.any((m) => m.contains('_deadField')), isTrue);
    expect(names.any((m) => m.contains('_deadFunction')), isTrue);
    expect(names.any((m) => m.contains('_aliveFunction')), isFalse);
    expect(names.any((m) => m.contains('_usedField')), isFalse);
  });

  test('unused_files flags never-imported lib files', () async {
    final project = createTempProject();
    addTearDown(() => project.deleteSync(recursive: true));
    writeFile(project, 'pubspec.yaml', 'name: myapp\n');
    writeFile(project, 'lib/used.dart', 'void u() {}\n');
    writeFile(project, 'lib/orphan.dart', 'void o() {}\n');
    writeFile(
      project,
      'bin/main.dart',
      "import 'package:myapp/used.dart';\n\nvoid main() => u();\n",
    );
    final result = await UnusedFilesGate().run(
      makeContext(
          project, ['lib/used.dart', 'lib/orphan.dart', 'bin/main.dart']),
    );
    expect(result.passed, isFalse);
    expect(result.violations.single.file, 'lib/orphan.dart');
  });

  test('unused_files reads imports from referenceFiles only', () async {
    final project = createTempProject();
    addTearDown(() => project.deleteSync(recursive: true));
    writeFile(project, 'pubspec.yaml', 'name: myapp\n');
    writeFile(project, 'lib/screen.dart', 'void s() {}\n');
    writeFile(project, 'lib/router.dart', "import 'screen.dart';\n");
    final analyzed = makeContext(project, ['lib/screen.dart']);
    final result = await UnusedFilesGate().run(
      GateContext(
        projectRoot: analyzed.projectRoot,
        config: analyzed.config,
        files: analyzed.files,
        referenceFiles: [
          ...analyzed.files,
          p.join(project.path, 'lib/router.dart'),
        ],
      ),
    );
    // screen.dart is imported by the reference-only router, and the
    // router itself is never a candidate because it is not analyzed.
    expect(result.passed, isTrue);
  });
}
