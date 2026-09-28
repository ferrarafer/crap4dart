import 'dart:io';

/// Variables git exports to hooks that pin the repository. With `GIT_DIR`
/// set and no `GIT_WORK_TREE`, git treats the current directory as the
/// work-tree root, so a hook running crap4dart in a sub-package (e.g.
/// `app/`) would resolve paths against the package instead of the
/// repository.
const Set<String> _repoPinningVariables = {'GIT_DIR', 'GIT_WORK_TREE'};

/// [parent] without the variables that pin git to a repository, so git
/// discovers it from the working directory. `GIT_INDEX_FILE` is kept: a
/// pre-commit hook for `git commit <paths>` stages into a temporary index
/// that `--staged` must read.
Map<String, String> gitEnvironment(Map<String, String> parent) => {
      for (final entry in parent.entries)
        if (!_repoPinningVariables.contains(entry.key)) entry.key: entry.value,
    };

/// Runs `git` with [args] in [workingDirectory], discovering the
/// repository from there even when invoked from a git hook.
Future<ProcessResult> runGit(
  List<String> args, {
  required String workingDirectory,
}) =>
    Process.run(
      'git',
      args,
      workingDirectory: workingDirectory,
      environment: gitEnvironment(Platform.environment),
      includeParentEnvironment: false,
    );
