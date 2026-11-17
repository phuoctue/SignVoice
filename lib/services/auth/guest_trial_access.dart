class GuestTrialAccess {
  GuestTrialAccess.fromJson(Map<String, dynamic> data)
    : state = data['state'] as String,
      dataState = data['dataState'] as String? ?? 'unknown',
      serverNow = DateTime.parse(data['serverNow'] as String),
      startedAt = _date(data['startedAt']),
      expiresAt = _date(data['expiresAt']),
      dataRetainedUntil = _date(data['dataRetainedUntil']),
      nextTrialAvailableAt = _date(data['nextTrialAvailableAt']),
      dataVersion = data['dataVersion'] as int?,
      allowedActions = Set<String>.from(data['allowedActions'] as List? ?? []);

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
  final String state, dataState;
  final DateTime serverNow;
  final DateTime? startedAt, expiresAt, dataRetainedUntil, nextTrialAvailableAt;
  final int? dataVersion;
  final Set<String> allowedActions;
  bool allows(String action) => allowedActions.contains(action);
  Duration get remaining {
    if (dataState != 'trial_active' || expiresAt == null) return Duration.zero;
    final value = expiresAt!.difference(serverNow);
    return value.isNegative ? Duration.zero : value;
  }
}
