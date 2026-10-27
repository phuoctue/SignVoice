import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'api_config.dart';

http.Client createHttpClient() => IOClient(
  HttpClient()
    ..idleTimeout = const Duration(seconds: 60)
    ..connectionTimeout = ApiConfig.connectTimeout,
);
