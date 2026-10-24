import 'package:flutter/foundation.dart';

import 'dart:async';

import '../models/user_model.dart';
import '../services/auth/auth_service.dart';
import '../services/api/api_exception.dart';
import '../services/auth/guest_trial_access.dart';

enum AuthState { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService, Stopwatch? trialClock})
    : _authService = authService ?? AuthService.instance,
      _trialClock = trialClock ?? Stopwatch() {
    _authService.sessionInvalidated.addListener(_sessionExpired);
  }
  final AuthService _authService;
  int _epoch = 0;
  bool _disposed = false;
  AuthState _state = AuthState.initial;
  UserModel? _user;
  String? _errorMessage;
  GuestTrialAccess? _trial;
  Timer? _trialTimer;
  final Stopwatch _trialClock;
  bool trialLoading = false;
  String? trialError;
  GuestTrialAccess? get trial => _trial;
  Duration get trialRemaining {
    final remaining =
        (_trial?.remaining ?? Duration.zero) - _trialClock.elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get trialExpired =>
      _trial?.state == 'expired' ||
      _trial?.state == 'active' && trialRemaining == Duration.zero;
  void _clearTrial() {
    _trialTimer?.cancel();
    _trialClock
      ..stop()
      ..reset();
    _trial = null;
    trialLoading = false;
    trialError = null;
  }

  Future<void> loadGuestTrial({bool start = false}) async {
    if (!isAuthenticated || _user?.isGuest != true || trialLoading) return;
    final epoch = _epoch, id = _user!.id;
    trialLoading = true;
    trialError = null;
    _notify();
    try {
      final value = await _authService.guestTrial(start: start);
      if (!_current(epoch) || _user?.id != id) return;
      _trial = value;
      _trialClock
        ..reset()
        ..start();
      _trialTimer?.cancel();
      if (value.state == 'active') {
        _trialTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!_current(epoch) || _user?.id != id) {
            timer.cancel();
            return;
          }
          if (trialExpired) timer.cancel();
          _notify();
        });
      }
    } catch (error) {
      if (_current(epoch) && _user?.id == id) trialError = _message(error);
    } finally {
      if (_current(epoch) && _user?.id == id) {
        trialLoading = false;
        _notify();
      }
    }
  }

  int get accountEpoch => _epoch;
  AuthState get state => _state;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated =>
      _state == AuthState.authenticated && _user != null;
  bool get isLoading => _state == AuthState.loading;
  bool get isAdmin => isAuthenticated && _user!.isAdmin;
  bool get isStaff => isAuthenticated && _user!.isStaff;
  bool can(String permission) =>
      isAuthenticated && _user!.hasPermission(permission);
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionExpired() {
    _clearTrial();
    _epoch++;
    _user = null;
    _state = AuthState.unauthenticated;
    _errorMessage = 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    _notify();
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : 'Không thể xác thực. Vui lòng thử lại.';
  Future<bool> _authenticate(Future<UserModel> Function() request) async {
    _clearTrial();
    final epoch = ++_epoch, previous = _user;
    _state = AuthState.loading;
    _errorMessage = null;
    _notify();
    try {
      final result = await request();
      if (!_current(epoch)) return false;
      _user = result;
      _state = AuthState.authenticated;
      _notify();
      return true;
    } catch (error) {
      if (!_current(epoch)) return false;
      _user = previous;
      _state = previous == null ? AuthState.error : AuthState.authenticated;
      _errorMessage = _message(error);
      _notify();
      return false;
    }
  }

  Future<void> initialize() async {
    _clearTrial();
    final epoch = ++_epoch;
    _state = AuthState.loading;
    _notify();
    try {
      final result = await _authService.restoreSession();
      if (!_current(epoch)) return;
      _user = result;
      _state = result == null
          ? AuthState.unauthenticated
          : AuthState.authenticated;
      _notify();
    } catch (error) {
      if (!_current(epoch)) return;
      _user = null;
      _state = AuthState.unauthenticated;
      _errorMessage = _message(error);
      _notify();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
  }) => _authenticate(
    () => _authService.register(
      email: email,
      password: password,
      displayName: displayName,
    ),
  );
  Future<bool> login({required String email, required String password}) =>
      _authenticate(() => _authService.login(email: email, password: password));
  Future<bool> loginAsGuest() => _authenticate(_authService.loginAsGuest);
  Future<bool> convertGuest({
    required String email,
    required String password,
    required String displayName,
  }) => _authenticate(
    () => _authService.convertGuest(
      email: email,
      password: password,
      displayName: displayName,
    ),
  );
  Future<Map<String, bool>> oauthProviders() => _authService.oauthProviders();
  Future<void> startOAuth(String provider) => _authService.startOAuth(provider);
  Future<bool> completeOAuth() => _authenticate(_authService.completeOAuth);
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final epoch = _epoch;
    try {
      await _authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (_current(epoch)) {
        _user = null;
        _state = AuthState.unauthenticated;
        _errorMessage = null;
        _epoch++;
        _notify();
      }
      return _state == AuthState.unauthenticated;
    } catch (error) {
      if (_current(epoch)) {
        _errorMessage = _message(error);
        _notify();
      }
      return false;
    }
  }

  Future<void> logout() async {
    _clearTrial();
    final epoch = ++_epoch;
    try {
      await _authService.logout();
    } catch (_) {
      /* The local session is still cleared by the service. */
    } finally {
      if (_current(epoch)) {
        _user = null;
        _state = AuthState.unauthenticated;
        _errorMessage = null;
        _notify();
      }
    }
  }

  Future<void> refreshUser() async {
    if (!isAuthenticated) return;
    final epoch = _epoch, id = _user!.id;
    try {
      final result = await _authService.getCurrentUser();
      if (_current(epoch) && _user?.id == id) {
        _user = result;
        _notify();
      }
    } on UnauthorizedException {
      if (_current(epoch)) _sessionExpired();
    } catch (error) {
      if (_current(epoch)) {
        _errorMessage = _message(error);
        _notify();
      }
    }
  }

  void clearError() {
    _errorMessage = null;
    if (_state == AuthState.error) {
      _state = _user == null
          ? AuthState.unauthenticated
          : AuthState.authenticated;
    }
    _notify();
  }

  @override
  void dispose() {
    _trialTimer?.cancel();
    _disposed = true;
    _epoch++;
    _authService.sessionInvalidated.removeListener(_sessionExpired);
    super.dispose();
  }
}
