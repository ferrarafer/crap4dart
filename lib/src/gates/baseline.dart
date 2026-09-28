import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'gate.dart';

/// Baseline file name, relative to the project root.
const String baselineFileName = '.crap-baseline.json';

final RegExp _number = RegExp(r'\d+(?:\.\d+)?');

/// Stored gate violations a project starts from; `check --baseline`
/// fails only on violations not present here.
///
/// Violations are matched on gate, file and message *shape* (the
/// message with every number replaced by `#`), never on line numbers,
/// so edits that shift code do not turn old debt into new violations.
/// Each key keeps one entry per stored violation: a file that had two
/// baselined violations of a shape may still have two, not three. When
/// both sides carry a [GateViolation.measure], a stored entry covers a
/// current violation only if the measure did not grow (a 1856-line file
/// may shrink, but not reach 1900 lines).
class Baseline {
  /// Creates a [Baseline] over stored measures grouped by key; a `null`
  /// measure covers any current value.
  const Baseline(this.entries);

  /// Loads the baseline of [projectRoot], or returns an empty baseline
  /// when no baseline file exists. Version 1 files (keyed by line) load
  /// too: their line is ignored and, lacking measures, their entries
  /// cover any current value.
  factory Baseline.load(String projectRoot) {
    final file = File(p.join(projectRoot, baselineFileName));
    if (!file.existsSync()) return const Baseline({});
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final entries = <String, List<num?>>{};
      for (final entry in json['violations'] as List<dynamic>? ?? const []) {
        if (entry is! Map<String, dynamic>) continue;
        final key = _key(entry['gate'] as String, entry['file'] as String,
            entry['message'] as String);
        (entries[key] ??= []).add(entry['measure'] as num?);
      }
      return Baseline(entries);
    } on FormatException {
      return const Baseline({});
    }
  }

  /// Stored measures per violation key ("gate|file|shape").
  final Map<String, List<num?>> entries;

  /// Returns the violations of [gateId] in [violations] that the
  /// baseline does not cover, in their original order.
  List<GateViolation> uncovered(
    String gateId,
    List<GateViolation> violations,
  ) {
    final groups = <String, List<GateViolation>>{};
    for (final violation in violations) {
      final key = _key(gateId, violation.file, violation.message);
      (groups[key] ??= []).add(violation);
    }
    final fresh = <GateViolation>{};
    groups.forEach((key, current) {
      fresh.addAll(_unmatched(current, entries[key] ?? const []));
    });
    return [
      for (final violation in violations)
        if (fresh.contains(violation)) violation,
    ];
  }

  /// Matches [current] against [stored] one-to-one, largest measures
  /// first: each current violation takes the largest remaining stored
  /// entry if that entry is not smaller. Greedy on sorted lists
  /// maximizes the number of matches.
  static List<GateViolation> _unmatched(
    List<GateViolation> current,
    List<num?> stored,
  ) {
    final budget = [for (final m in stored) m ?? double.infinity]
      ..sort((a, b) => b.compareTo(a));
    final sorted = [...current]
      ..sort((a, b) => (b.measure ?? 0).compareTo(a.measure ?? 0));
    final unmatched = <GateViolation>[];
    var next = 0;
    for (final violation in sorted) {
      if (next < budget.length && (violation.measure ?? 0) <= budget[next]) {
        next++;
      } else {
        unmatched.add(violation);
      }
    }
    return unmatched;
  }

  static String _key(String gate, String file, String message) =>
      '$gate|$file|${message.replaceAll(_number, '#')}';
}

/// Writes the current violations of [results] to the baseline file of
/// [projectRoot]. Returns the number of stored violations.
int writeBaseline(String projectRoot, List<GateResult> results) {
  final violations = <Map<String, Object?>>[];
  for (final result in results) {
    for (final violation in result.violations) {
      violations.add({
        'gate': result.gateId,
        'file': violation.file,
        'message': violation.message,
        if (violation.measure != null) 'measure': violation.measure,
      });
    }
  }
  final file = File(p.join(projectRoot, baselineFileName));
  file.writeAsStringSync(
    JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'violations': violations,
    }),
  );
  return violations.length;
}

/// Strips baseline-covered violations from [result]; a gate with every
/// violation covered passes.
GateResult applyBaseline(String gateId, GateResult result, Baseline baseline) {
  if (result.passed || result.violations.isEmpty) return result;
  final fresh = baseline.uncovered(gateId, result.violations);
  if (fresh.length == result.violations.length) return result;
  return GateResult(
    gateId: gateId,
    passed: fresh.isEmpty,
    violations: fresh,
    summary: result.summary,
    warning: result.warning,
  );
}
