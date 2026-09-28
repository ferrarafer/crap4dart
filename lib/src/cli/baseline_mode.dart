import 'dart:io';

import '../gates/baseline.dart';
import '../gates/gate_runner.dart';
import 'exit_codes.dart';

/// Which baseline flag `check` was given.
enum BaselineMode {
  /// No baseline flag: report every violation.
  none,

  /// `--save-baseline`: record current violations, always succeed.
  save,

  /// `--baseline`: report only violations the baseline does not cover.
  apply,

  /// `--tighten-baseline`: ratchet the baseline down, then [apply].
  tighten;

  /// Picks the mode from the `check` flags (`--save-baseline` wins).
  static BaselineMode fromFlags({
    required bool save,
    required bool apply,
    required bool tighten,
  }) {
    if (save) return BaselineMode.save;
    if (tighten) return BaselineMode.tighten;
    return apply ? BaselineMode.apply : BaselineMode.none;
  }

  /// Rejects a partial file selection for [tighten] (entries of
  /// unchecked files would be dropped), printing why. Call before the
  /// gates run.
  bool validate({required bool partialSelection}) {
    if (this != BaselineMode.tighten || !partialSelection) return true;
    stderr.writeln('Error: --tighten-baseline needs a full run '
        '(no --changed, --staged, --diff or paths): entries of unchecked '
        'files would be dropped.');
    return false;
  }

  /// Applies this mode to the gate [result] of [projectRoot]: writes or
  /// tightens the baseline file and filters covered violations. Returns
  /// `null` (after printing why) when there is no baseline to tighten.
  GateRunResult? process(String projectRoot, GateRunResult result) {
    switch (this) {
      case BaselineMode.none:
        return result;
      case BaselineMode.save:
        final count = writeBaseline(projectRoot, result.results);
        stderr.writeln('Baseline saved: $count violation(s) recorded in '
            '$baselineFileName');
        return result;
      case BaselineMode.tighten:
        if (!_tighten(projectRoot, result)) return null;
        return _apply(projectRoot, result);
      case BaselineMode.apply:
        return _apply(projectRoot, result);
    }
  }

  /// The exit code for the processed [result]; saving always succeeds.
  int exitCode(GateRunResult result) =>
      this == BaselineMode.save || result.passed
          ? ExitCodes.success
          : ExitCodes.thresholdExceeded;

  static bool _tighten(String projectRoot, GateRunResult result) {
    final stats = tightenBaseline(projectRoot, result.results);
    if (stats == null) {
      stderr.writeln('Error: no $baselineFileName to tighten; create one '
          'with --save-baseline first.');
      return false;
    }
    stderr.writeln('Baseline tightened: ${stats.kept} kept '
        '(${stats.lowered} lowered), ${stats.removed} removed, '
        '${stats.notAdded} new or grown violation(s) not accepted.');
    return true;
  }

  static GateRunResult _apply(String projectRoot, GateRunResult result) {
    final baseline = Baseline.load(projectRoot);
    return GateRunResult([
      for (final gateResult in result.results)
        applyBaseline(gateResult.gateId, gateResult, baseline),
    ], diffMode: result.diffMode);
  }
}
