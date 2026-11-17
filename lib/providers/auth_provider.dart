import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'dart:async';

import '../models/user_model.dart';
import '../services/auth/auth_service.dart';
import '../services/api/api_exception.dart';
import '../services/auth/guest_trial_access.dart';
import '../services/auth/guest_grant_operation.dart';

enum AuthState { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService, Stopwatch? trialClock})
    : _authService = authService ?? AuthService.instance,
      _trialClock = trialClock ?? Stopwatch() {
    _authService.sessionInvalidated.addListener(_sessionExpired);
    _authService.guestTrialExpired.addListener(_guestTrialDenied);
  }
  final AuthService _authService;
  int _epoch = 0;
  bool _disposed = false;
  AuthState _state = AuthState.initial;
  UserModel? _user;
  Future<void>? _userRefresh;
  int? _userRefreshEpoch;
  int _profileRevision = 0;
  String? _errorMessage;
  bool guestResumePending = false;
  bool _restoringSession = false;
  bool _convertingGuest = false;
  int? _conversionEpoch;
  bool _conversionInvalidated = false;
  bool conversionNeedsLogin = false;
  ApiException? conversionError;
  bool guestOperationBusy = false;
  int? _discardEpoch;
  bool guestOperationUnknown = false;
  String? guestOperationMessage;
  bool noticeDismissed = false;
  void dismissGuestNotice() {
    noticeDismissed = true;
    _notify();
  }

  bool guestAllows(String action) =>
      isAuthenticated &&
      _user?.isGuest == true &&
      !trialLoading &&
      trialError == null &&
      !guestOperationBusy &&
      !guestOperationUnknown &&
      _trial?.allows(action) == true &&
      (action != 'convert' ||
          conversionDeadline == null ||
          conversionDeadline!.isAfter(
            _trial!.serverNow.add(_trialClock.elapsed),
          ));
  DateTime? get conversionDeadline {
    final data = _trial?.dataRetainedUntil;
    final cutoff = _user?.legacyGuestSessionCutoffAt;
    if (data == null) return cutoff;
    return cutoff != null && cutoff.isBefore(data) ? cutoff : data;
  }

  bool get isRestoringSession => _restoringSession;

  void acceptRestoredGuest() {
    guestResumePending = false;
    _notify();
  }

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
      _trial != null &&
      (_trial?.dataState != 'trial_active' || trialRemaining == Duration.zero);
  void _clearTrial() {
    _trialTimer?.cancel();
    _trialClock
      ..stop()
      ..reset();
    _trial = null;
    trialLoading = false;
    trialError = null;
  }

  Future<void> loadGuestTrial() async {
    if (!isAuthenticated || _user?.isGuest != true || trialLoading) return;
    final epoch = _epoch, id = _user!.id;
    trialLoading = true;
    trialError = null;
    _notify();
    try {
      final value = await _authService.guestTrial();
      if (!_current(epoch) || _user?.id != id) return;
      _trial = value;
      _trialClock
        ..reset()
        ..start();
      _trialTimer?.cancel();
      if (value.dataState == 'trial_active') {
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

  void _guestTrialDenied() {
    if (!_disposed) unawaited(loadGuestTrial());
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
    _restoringSession = false;
    _clearTrial();
    if (_conversionEpoch == _epoch) {
      _conversionInvalidated = true;
    } else if (_discardEpoch == _epoch) {
      // Keep the request identity until its acknowledgement is examined.
    } else {
      _epoch++;
    }
    _user = null;
    _state = AuthState.unauthenticated;
    _errorMessage = 'Phiên đăng nhập đã hết hạn. Với tài khoản khách, dữ liệu có thể vẫn còn, nhưng không thể xác minh quyền để giữ hoặc xóa dữ liệu lúc này. Vui lòng đăng nhập lại.';
    _notify();
  }

  String _message(Object error) {
    if (error is ApiException &&
        error.statusCode == 409 &&
        error.details?.containsKey('nextTrialAvailableAt') == true) {
      final next = DateTime.tryParse(
        error.details!['nextTrialAvailableAt'] as String? ?? '',
      );
      return next == null
          ? 'Chưa cấp lượt thử. Hãy kiểm tra lại trạng thái.'
          : 'Chưa cấp lượt thử cho yêu cầu này. Thử lại lúc ${DateFormat('HH:mm dd/MM/yyyy').format(next.toLocal())}. Cần xác nhận một yêu cầu mới.';
    }
    return error is ApiException
        ? error.message
        : 'Không thể xác thực. Vui lòng thử lại.';
  }

  Future<bool> _authenticate(
    Future<UserModel> Function() request, {
    bool guestGrant = false,
  }) async {
    _restoringSession = false;
    guestResumePending = false;
    final epoch = ++_epoch, previous = _user;
    _state = AuthState.loading;
    _errorMessage = null;
    _notify();
    try {
      final result = await request();
      if (!_current(epoch)) return false;
      _user = result;
      _clearTrial();
      guestOperationUnknown = false;
      guestOperationMessage = null;
      _state = AuthState.authenticated;
      _notify();
      if (result.isGuest) await loadGuestTrial();
      return true;
    } catch (error) {
      if (!_current(epoch)) return false;
      _user = previous;
      _state = previous == null ? AuthState.error : AuthState.authenticated;
      _errorMessage =
          guestGrant &&
              (error is! ApiException ||
                  error.statusCode == null ||
                  error.statusCode! >= 500)
          ? 'Chưa xác nhận được lượt thử. Hãy kiểm tra kết nối và thử lại cùng yêu cầu.'
          : _message(error);
      _notify();
      return false;
    }
  }

  Future<void> initialize() async {
    _clearTrial();
    _restoringSession = true;
    final epoch = ++_epoch;
    _state = AuthState.loading;
    _notify();
    try {
      final result = await _authService.restoreSession();
      if (!_current(epoch)) return;
      _user = result;
      _restoringSession = false;
      _state = result == null
          ? AuthState.unauthenticated
          : AuthState.authenticated;
      guestResumePending = false;
      _notify();
      if (result?.isGuest == true) await loadGuestTrial();
    } catch (error) {
      if (!_current(epoch)) return;
      _restoringSession = false;
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
  }) => _registerAndRequireLogin(
    () => _authService.register(
      email: email,
      password: password,
      displayName: displayName,
    ),
  );
  Future<bool> login({required String email, required String password}) =>
      _authenticate(() => _authService.login(email: email, password: password));
  Future<bool> loginAsGuest() async {
    if (isLoading || guestOperationBusy || _user != null) return false;
    return _authenticate(_authService.loginAsGuest, guestGrant: true);
  }

  Future<bool> startSeparateGuestTrial() async {
    if (isLoading || guestOperationBusy || _user != null) return false;
    return _authenticate(() async {
      await GuestGrantOperation.beginSeparateOperation();
      return _authService.loginAsGuest();
    }, guestGrant: true);
  }

  Future<bool> replaceGuest() async {
    if (!guestAllows('new_trial') || _trial?.dataVersion == null) return false;
    final version = _trial!.dataVersion!, ownerId = _user!.id;
    final success = await _authenticate(
      () => _authService.replaceGuest(dataVersion: version, ownerId: ownerId),
    );
    if (!success && isAuthenticated) {
      guestOperationMessage = 'Chưa xác nhận được lượt mới. Kiểm tra trạng thái trước khi tiếp tục; không thể kết luận dữ liệu cũ đã bị xóa.';
      guestOperationUnknown = true;
      _notify();
    }
    return success;
  }

  Future<bool> discardGuest() async {
    if (!guestAllows('discard') || _trial?.dataVersion == null) return false;
    final epoch = _epoch, version = _trial!.dataVersion!;
    guestOperationBusy = true;
    _discardEpoch = epoch;
    guestOperationMessage = null;
    _notify();
    try {
      await _authService.discardGuest(version);
      if (!_current(epoch)) return false;
      _epoch++;
      _clearTrial();
      _user = null;
      _state = AuthState.unauthenticated;
      guestResumePending = false;
      _errorMessage = null;
      guestOperationMessage = 'Đã xóa dữ liệu khách theo xác nhận của máy chủ.';
      return true;
    } catch (error) {
      // A 401 after a lost commit proves no deletion; never turn it into success.
      if (!_current(epoch)) return false;
      guestOperationUnknown =
          !(error is ApiException &&
              (error.statusCode == 409 ||
                  error.statusCode == 400 ||
                  error.statusCode == 429));
      guestOperationMessage = guestOperationUnknown
          ? 'Chưa xác nhận được việc xóa dữ liệu. Mất phiên không chứng minh dữ liệu đã được xóa. Hãy kiểm tra kết nối và thử kiểm tra trạng thái; không thể xác nhận nếu phiên đã hết hạn.'
          : 'Chưa xóa dữ liệu. Hãy kiểm tra lại trạng thái rồi xác nhận lại.';
      if (_current(epoch) && !guestOperationUnknown) await loadGuestTrial();
      return false;
    } finally {
      guestOperationBusy = false;
      _discardEpoch = null;
      _notify();
    }
  }

  Future<void> reconcileGuestOperation() async {
    await loadGuestTrial();
    if (isAuthenticated && trialError == null && !trialLoading) {
      guestOperationUnknown = false;
      _notify();
    }
  }

  Future<bool> convertGuest({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (_convertingGuest || isLoading || !guestAllows('convert')) return false;
    final previous = _user;
    final epoch = ++_epoch;
    _convertingGuest = true;
    _conversionEpoch = epoch;
    _conversionInvalidated = false;
    conversionNeedsLogin = false;
    conversionError = null;
    _errorMessage = null;
    _state = AuthState.loading;
    _notify();
    try {
      await _authService.convertGuest(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (!_current(epoch)) return false;
      _clearTrial();
      guestResumePending = false;
      _user = null;
      _state = AuthState.unauthenticated;
      _notify();
      return true;
    } catch (error) {
      if (!_current(epoch)) return false;
      final knownRejection =
          !_conversionInvalidated &&
          error is ApiException &&
          (error.code == 'AUTH_EMAIL_ALREADY_EXISTS' ||
              error.code == 'VALIDATION_ERROR' ||
              error.statusCode == 403 ||
              error.statusCode == 409 ||
              error.statusCode == 429);
      var stillGuest = knownRejection;
      if (!knownRejection && !_conversionInvalidated) {
        try {
          final current = await _authService.getCurrentUser();
          if (!_current(epoch)) return false;
          stillGuest = current.isGuest && current.id == previous!.id;
        } on UnauthorizedException {
          // The normal API path already cleared the denied session.
        } catch (_) {
          stillGuest = true;
          guestOperationUnknown = true;
          guestOperationMessage = 'Chưa xác nhận được kết quả chuyển tài khoản. Hãy kiểm tra lại trạng thái trước khi tiếp tục.';
        }
      }
      if (!_current(epoch)) return false;
      if (stillGuest && !_conversionInvalidated) {
        conversionError = error is ApiException ? error : null;
        _user = previous;
        _state = AuthState.authenticated;
        _errorMessage = !knownRejection
            ? 'Chưa xác nhận được kết quả chuyển tài khoản. Phiên khách vẫn được giữ; hãy kiểm tra trạng thái trước khi thử lại.'
            : error.statusCode == 429
            ? 'Bạn đã thử quá nhiều lần. Vui lòng thử lại sau.'
            : error.code == 'AUTH_EMAIL_ALREADY_EXISTS'
            ? 'Email đã được dùng.'
            : error.code == 'VALIDATION_ERROR'
            ? 'Vui lòng kiểm tra thông tin đã nhập.'
            : _message(error);
        if (!guestOperationUnknown) await loadGuestTrial();
        if (_conversionInvalidated) conversionNeedsLogin = true;
      } else {
        if (!_conversionInvalidated) await _authService.clearLocalSession();
        if (!_current(epoch)) return false;
        conversionNeedsLogin = true;
        _clearTrial();
        guestResumePending = false;
        _user = null;
        _state = AuthState.unauthenticated;
        _errorMessage =
            'Nếu bạn đã tạo tài khoản, hãy đăng nhập bằng email này.';
      }
      _notify();
      return false;
    } finally {
      _convertingGuest = false;
      _conversionEpoch = null;
    }
  }

  Future<Map<String, bool>> oauthProviders() => _authService.oauthProviders();
  Future<bool> _registerAndRequireLogin(
    Future<UserModel> Function() request,
  ) async {
    final previous = _user;
    final epoch = ++_epoch;
    _state = AuthState.loading;
    _errorMessage = null;
    _notify();
    try {
      await request();
      if (!_current(epoch)) return false;
      _clearTrial();
      _user = null;
      _state = AuthState.unauthenticated;
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

  Future<void> startOAuth(String provider) => _authService.startOAuth(provider);
  Future<bool> completeOAuth() => _authenticate(_authService.completeOAuth);
  Future<bool> loginWithGoogle() => _authenticate(_authService.signInGoogle);
  Future<bool> linkGoogle() async {
    final epoch = _epoch, id = _user?.id;
    _errorMessage = null;
    try {
      final user = await _authService.linkGoogle();
      if (!_current(epoch) || _user?.id != id || user.id != id) return false;
      _profileRevision++;
      _user = user;
      _notify();
      return true;
    } catch (error) {
      if (_current(epoch)) {
        _errorMessage = _message(error);
        _notify();
      }
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final epoch = _epoch;
    try {
      if (_user?.accountType == AccountType.google) {
        await _authService.setPassword(newPassword: newPassword);
      } else {
        await _authService.changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
      }
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
    _restoringSession = false;
    guestResumePending = false;
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

  Future<void> refreshUser() {
    if (!isAuthenticated) return Future.value();
    if (_userRefresh != null && _userRefreshEpoch == _epoch) {
      return _userRefresh!;
    }
    final epoch = _epoch;
    late final Future<void> request;
    request = _refreshUser(epoch, _user!.id).whenComplete(() {
      if (identical(_userRefresh, request)) {
        _userRefresh = null;
        _userRefreshEpoch = null;
      }
    });
    _userRefreshEpoch = epoch;
    return _userRefresh = request;
  }

  Future<void> _refreshUser(int epoch, String id) async {
    final profileRevision = _profileRevision;
    try {
      final result = await _authService.getCurrentUser();
      if (_current(epoch) && _user?.id == id) {
        _user = profileRevision == _profileRevision
            ? result
            : result.copyWith(
                displayName: _user!.displayName,
                email: _user!.email,
                avatarUrl: _user!.avatarUrl,
              );
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

  /// Update display fields only after the profile endpoint acknowledged them.
  /// Authorization, roles, status and account identity remain server controlled.
  void applyAcknowledgedProfile({
    required String userId,
    required String displayName,
    required String email,
    required String avatarUrl,
  }) {
    if (!isAuthenticated || _user?.id != userId) return;
    _profileRevision++;
    _user = _user!.copyWith(
      displayName: displayName,
      email: email,
      avatarUrl: avatarUrl,
    );
    _notify();
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
    _authService.guestTrialExpired.removeListener(_guestTrialDenied);
    super.dispose();
  }
}
