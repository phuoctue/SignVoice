class PushNotice {
  const PushNotice(this.notificationId, this.title, this.body, this.route);
  final String notificationId, title, body, route;
  int get id =>
      int.parse(notificationId.substring(0, 8), radix: 16) & 0x7fffffff;
}

PushNotice? pushNoticeFor(
  Map<String, dynamic> data,
  String? owner, {
  DateTime? now,
}) {
  if (owner == null || data['userId'] != owner) return null;
  final expires = int.tryParse('${data['expiresAt']}');
  final id = data['notificationId'],
      title = data['title'],
      body = data['body'],
      route = data['route'];
  if (expires == null ||
      expires <= (now ?? DateTime.now()).millisecondsSinceEpoch ||
      id is! String ||
      !RegExp(r'^[a-f0-9]{24}$').hasMatch(id) ||
      title is! String ||
      title.isEmpty ||
      title.length > 160 ||
      body is! String ||
      body.length > 1024 ||
      !const {'/notifications', '/learn', '/learn?tab=1'}.contains(route)) {
    return null;
  }
  return PushNotice(id, title, body, route as String);
}
