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
    final entries = <String, List<num?>>{};
    for (final entry in _readEntries(projectRoot) ?? const []) {
      final key = _key(entry['gate'] as String, entry['file'] as String,
          entry['message'] as String);
      (entries[key] ??= []).add(entry['measure'] as num?);
    }
    return Baseline(entries);
  }

  /// The raw stored entries of [projectRoot]'s baseline file, or `null`
  /// when there is no file; a malformed file has no entries.
  static List<Map<String, dynamic>>? _readEntries(String projectRoot) {
    final file = File(p.join(projectRoot, baselineFileName));
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return [
        for (final entry in json['violations'] as List<dynamic>? ?? const [])
          if (entry is Map<String, dynamic>) entry,
      ];
    } on FormatException {
      return const [];
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
    final covered = matches(gateId, violations);
    return [
      for (final violation in violations)
        if (!covered.containsKey(violation)) violation,
    ];
  }

  /// Maps each violation of [gateId] the baseline covers to the stored
  /// ceiling it matched (`double.infinity` for entries without a
  /// measure). Uncovered violations are absent.
  Map<GateViolation, num> matches(
    String gateId,
    List<GateViolation> violations,
  ) =>
      pairUp(gateId, violations).matched;

  /// Pairs the violations of [gateId] with stored entries of the same key.
  ///
  /// `matched` maps covered violations to the ceiling they matched.
  /// `grown` maps uncovered violations that still have a leftover stored
  /// entry of their key (they exist in the baseline but got worse) to
  /// that entry's ceiling. Violations in neither map are new.
  ({Map<GateViolation, num> matched, Map<GateViolation, num> grown}) pairUp(
    String gateId,
    List<GateViolation> violations,
  ) {
    final groups = <String, List<GateViolation>>{};
    for (final violation in violations) {
      final key = _key(gateId, violation.file, violation.message);
      (groups[key] ??= []).add(violation);
    }
    final matched = Map<GateViolation, num>.identity();
    final grown = Map<GateViolation, num>.identity();
    groups.forEach((key, current) {
      _match(current, entries[key] ?? const [], matched, grown);
    });
    return (matched: matched, grown: grown);
  }

  /// Matches [current] against [stored] one-to-one, largest measures
  /// first: each current violation takes the largest remaining stored
  /// entry if that entry is not smaller. Greedy on sorted lists
  /// maximizes the number of matches. Unmatched violations then take the
  /// leftover entries (largest first) as [grown].
  static void _match(
    List<GateViolation> current,
    List<num?> stored,
    Map<GateViolation, num> matched,
    Map<GateViolation, num> grown,
  ) {
    final budget = [for (final m in stored) m ?? double.infinity]
      ..sort((a, b) => b.compareTo(a));
    final sorted = [...current]
      ..sort((a, b) => (b.measure ?? 0).compareTo(a.measure ?? 0));
    final unmatched = <GateViolation>[];
    var next = 0;
    for (final violation in sorted) {
      if (next < budget.length && (violation.measure ?? 0) <= budget[next]) {
        matched[violation] = budget[next++];
      } else {
        unmatched.add(violation);
      }
    }
    for (final violation in unmatched) {
      if (next == budget.length) break;
      grown[violation] = budget[next++];
    }
  }

  static String _key(String gate, String file, String message) =>
      '$gate|$file|${message.replaceAll(_number, '#')}';
}

/// Writes the current violations of [results] to the baseline file of
/// [projectRoot]. Returns the number of stored violations.
int writeBaseline(String projectRoot, List<GateResult> results) {
  final violations = [
    for (final result in results)
      for (final violation in result.violations)
        _entry(result.gateId, violation),
  ];
  _writeEntries(projectRoot, violations);
  return violations.length;
}

/// The stored form of [violation]; [ceiling] overrides its measure
/// (`double.infinity` means none).
Map<String, Object?> _entry(
  String gateId,
  GateViolation violation, {
  num? ceiling,
}) {
  final measure = ceiling ?? violation.measure;
  return {
    'gate': gateId,
    'file': violation.file,
    'message': violation.message,
    if (measure != null && measure != double.infinity) 'measure': measure,
  };
}

void _writeEntries(String projectRoot, List<Map<String, Object?>> entries) {
  File(p.join(projectRoot, baselineFileName)).writeAsStringSync(
    JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'violations': entries,
    }),
  );
}

/// What [tightenBaseline] changed.
class TightenStats {
  /// Creates [TightenStats].
  const TightenStats({
    required this.kept,
    required this.lowered,
    required this.removed,
    required this.notAdded,
  });

  /// Entries still in the baseline (including [lowered] ones).
  final int kept;

  /// Kept entries whose ceiling dropped to a smaller current measure.
  final int lowered;

  /// Entries dropped because their violation is gone.
  final int removed;

  /// Current violations the baseline does not cover (new, or grown past
  /// their ceiling); never accepted.
  final int notAdded;
}

/// Ratchets the baseline of [projectRoot] down to the violations in
/// [results], without ever accepting new ones: covered violations keep
/// an entry at their current (never larger) measure, entries no longer
/// matched are dropped, and uncovered violations are not added. Entries
/// of gates absent from [results] or skipped are kept unchanged. Returns
/// `null` when there is no baseline file.
TightenStats? tightenBaseline(String projectRoot, List<GateResult> results) {
  final stored = Baseline._readEntries(projectRoot);
  if (stored == null) return null;
  final baseline = Baseline.load(projectRoot);
  final ran = {
    for (final r in results)
      if (!r.skipped) r.gateId,
  };
  // Entries of gates that did not run are kept as they are.
  final entries = <Map<String, Object?>>[
    for (final entry in stored)
      if (!ran.contains(entry['gate'])) entry,
  ];
  var lowered = 0;
  var notAdded = 0;
  for (final result in results.where((r) => !r.skipped)) {
    final pairs = baseline.pairUp(result.gateId, result.violations);
    notAdded += result.violations.length - pairs.matched.length;
    // Violation order (as --save-baseline writes it): a no-op tighten
    // leaves the file unchanged.
    for (final violation in result.violations) {
      final ceiling = pairs.matched[violation];
      if (ceiling != null) {
        if ((violation.measure ?? ceiling) < ceiling) lowered++;
        entries.add(_entry(result.gateId, violation));
      } else if (pairs.grown[violation] case final old?) {
        // A grown violation still exists: keep its old ceiling so fixing
        // it back down is covered again (it keeps failing meanwhile).
        entries.add(_entry(result.gateId, violation, ceiling: old));
      }
    }
  }
  _writeEntries(projectRoot, entries);
  return TightenStats(
    kept: entries.length,
    lowered: lowered,
    removed: stored.length - entries.length,
    notAdded: notAdded,
  );
}

/// Strips baseline-covered violations from [result]; a gate with every
/// violation covered passes. Applies to `severity: warning` gates too
/// (their results count as passed but still carry violations).
GateResult applyBaseline(String gateId, GateResult result, Baseline baseline) {
  if (result.violations.isEmpty) return result;
  final fresh = baseline.uncovered(gateId, result.violations);
  if (fresh.length == result.violations.length) return result;
  return GateResult(
    gateId: gateId,
    passed: result.passed || fresh.isEmpty,
    violations: fresh,
    summary: result.summary,
    warning: result.warning && fresh.isNotEmpty,
  );
}
