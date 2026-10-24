import '../../services/api/sign_stream_connection.dart';

Future<Uri> quizCameraSocketUri({
  required String serviceUrl,
  required String gatewayUrl,
  required Future<String> Function() ticketLoader,
}) => signStreamSocketUri(
  serviceUrl: serviceUrl,
  gatewayUrl: gatewayUrl,
  ticketLoader: ticketLoader,
);
