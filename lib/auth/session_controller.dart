import 'dart:async';

import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class SessionController extends ChangeNotifier {
  SessionController(this.auth, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final AuthService auth;
  final DateTime Function() _clock;
  static const timeout = Duration(minutes: 1);
  WorkerIdentity? _worker;
  bool _locked = false;
  bool _hidden = false;
  bool _disposed = false;
  bool _busy = false;
  int _generation = 0;
  Timer? _timer;
  DateTime? _lastActivity;
  final Stopwatch _elapsed = Stopwatch();

  WorkerIdentity? get worker => _worker;
  bool get locked => _locked;
  bool get hidden => _hidden;
  bool get busy => _busy;
  String? get currentWorkerId {
    // Enforce deadline on access even if the timer has not been serviced yet.
    if (_expired) return null;
    return !_locked && !_hidden ? _worker?.id : null;
  }

  bool get _expired =>
      _worker != null &&
      _lastActivity != null &&
      (_elapsed.elapsed >= timeout ||
          _clock().difference(_lastActivity!) >= timeout);

  Future<void> signIn(
    String name,
    String password, {
    bool register = false,
  }) async {
    if (_busy || _worker != null) return;
    await _perform(
      () => register
          ? auth.register(name, password)
          : auth.authenticate(name, password),
    );
  }

  Future<void> unlock(String password) async {
    if (_busy || _worker == null || !_locked) return;
    final expectedId = _worker!.id;
    await _perform(() async {
      final result = await auth.authenticate(_worker!.username, password);
      if (result.id != expectedId) throw const AuthFailure('Account mismatch.');
      return result;
    });
  }

  Future<void> _perform(Future<WorkerIdentity> Function() action) async {
    final generation = ++_generation;
    _busy = true;
    notifyListeners();
    try {
      final result = await action();
      if (_disposed || generation != _generation) return;
      _worker = result;
      _locked = _hidden;
      if (!_locked) _resetDeadline();
    } finally {
      if (!_disposed && generation == _generation) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void activity() {
    if (_worker == null || _locked || _hidden) return;
    if (_expired) {
      lock();
      return;
    }
    _resetDeadline();
  }

  void _resetDeadline() {
    _lastActivity = _clock();
    _elapsed
      ..reset()
      ..start();
    _timer?.cancel();
    _timer = Timer(timeout, lock);
  }

  void lock() {
    if (_disposed || _worker == null || _locked) return;
    _locked = true;
    _timer?.cancel();
    notifyListeners();
  }

  void setForeground(bool foreground) {
    if (_disposed) return;
    _hidden = !foreground;
    if (foreground && _expired) _locked = true;
    // Returning before the deadline never resets the inactivity timer.
    notifyListeners();
  }

  void logout() {
    _generation++;
    _busy = false;
    _worker = null;
    _locked = false;
    _timer?.cancel();
    _elapsed.stop();
    _lastActivity = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }
}
