class GuestTrialAccess {
  GuestTrialAccess.fromJson(Map<String, dynamic> data)
    : state = data['state'] as String,
      remaining = data['expiresAt'] == null
          ? const Duration(minutes: 10)
          : DateTime.parse(data['expiresAt'] as String)
                .difference(DateTime.parse(data['serverNow'] as String));
  final String state;
  final Duration remaining;
}
