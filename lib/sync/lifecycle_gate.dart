/// One process-wide gate for pairing, trust setup, probes/status and sync.
/// Busy calls fail rather than queue work from a stale session.
class LifecycleGate {
  static bool _busy = false;
  static Future<T> run<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('Dashboard operation already running');
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}
