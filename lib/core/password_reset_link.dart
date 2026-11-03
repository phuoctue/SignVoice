/// The platform bridge passes only this internal route, never arbitrary URLs.
String? validatedPasswordResetRoute(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasFragment ||
      uri.path != '/reset-password' ||
      uri.queryParametersAll.length != 1) {
    return null;
  }
  final tokens = uri.queryParametersAll['token'];
  if (tokens == null ||
      tokens.length != 1 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(tokens.single)) {
    return null;
  }
  return Uri(
    path: '/reset-password',
    queryParameters: {'token': tokens.single},
  ).toString();
}
