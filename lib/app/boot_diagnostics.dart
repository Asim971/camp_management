import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One pre-frame step that degraded rather than aborting.
class BootFailure {
  const BootFailure(this.step, this.error);

  /// The step's name, e.g. `'sessionManager.restore'`. Stable enough to assert.
  final String step;

  /// The error, already rendered. No stack trace: this is read for "what came
  /// up degraded", not for debugging.
  final String error;

  @override
  String toString() => '$step: $error';
}

/// What degraded during `bootstrap`. Empty means a clean boot.
///
/// This exists so a guarded boot is OBSERVABLE. Guarding failures with a bare
/// catch is what `AuditFlusher.flush` used to do — silent, recurring, invisible
/// — and it is the failure mode P0.6 removes.
class BootDiagnostics {
  final List<BootFailure> _failures = [];

  List<BootFailure> get failures => List.unmodifiable(_failures);
  bool get isClean => _failures.isEmpty;

  void record(String step, Object error) =>
      _failures.add(BootFailure(step, error.toString()));
}

final bootDiagnosticsProvider = Provider<BootDiagnostics>(
  (ref) => BootDiagnostics(),
);
