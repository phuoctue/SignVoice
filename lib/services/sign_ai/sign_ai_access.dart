import '../api/api_client.dart';

Future<String> loadAiStreamTicket() async {
  final result = await ApiClient.instance.post(
    '/guest-trial/ai-ticket',
    body: {},
  );
  return result['data']['ticket'] as String;
}
