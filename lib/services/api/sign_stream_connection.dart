import '../sign_ai/sign_ai_config.dart';

Future<Uri> signStreamSocketUri({
  required String serviceUrl,
  required String gatewayUrl,
  required Future<String> Function() ticketLoader,
}) async {
  final service = Uri.parse(serviceUrl);
  final gateway = Uri.parse(gatewayUrl);
  var socket = SignAiConfig.socketUri(serviceUrl);
  // Compare HTTP origins before conversion: Dart has no default ws/wss port.
  if (service.origin == gateway.origin && socket.path == '/sign-ai/v1/stream') {
    socket = socket.replace(queryParameters: {'ticket': await ticketLoader()});
  }
  return socket;
}
