import 'dart:io';

import 'package:crap4dart/src/files/git_process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('gitEnvironment drops the variables git hooks pin the repo with', () {
    final env = gitEnvironment({
      'GIT_DIR': '/repo/.git/worktrees/x',
      'GIT_WORK_TREE': '/repo',
      'GIT_INDEX_FILE': '/repo/.git/index.lock',
      'PATH': '/usr/bin',
    });
    expect(
        env, {'GIT_INDEX_FILE': '/repo/.git/index.lock', 'PATH': '/usr/bin'});
  });

  test('runGit discovers the repository from a subdirectory', () async {
    final root = Directory.systemTemp.createTempSync('git_process');
    addTearDown(() => root.deleteSync(recursive: true));
    final pkg = Directory(p.join(root.path, 'pkg'))..createSync();
    await runGit(const ['init', '.'], workingDirectory: root.path);
    final result = await runGit(
      const ['rev-parse', '--show-toplevel'],
      workingDirectory: pkg.path,
    );
    expect(
      p.canonicalize('${result.stdout}'.trim()),
      p.canonicalize(root.resolveSymbolicLinksSync()),
    );
  });
}
