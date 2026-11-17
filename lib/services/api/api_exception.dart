/// Custom API exceptions
class ApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final Map<String, dynamic>? details;

  ApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.details,
  });

  @override
  String toString() =>
      'ApiException: $message (code: $code, status: $statusCode)';
}

class NetworkException extends ApiException {
  NetworkException({super.message = 'Network error occurred'})
    : super(code: 'NETWORK_ERROR');
}

class UnauthorizedException extends ApiException {
  UnauthorizedException({super.message = 'Unauthorized'})
    : super(code: 'UNAUTHORIZED', statusCode: 401);
}

class ForbiddenException extends ApiException {
  ForbiddenException({
    super.message = 'Forbidden',
    super.code = 'FORBIDDEN',
    super.details,
  }) : super(statusCode: 403);
}

class NotFoundException extends ApiException {
  NotFoundException({super.message = 'Resource not found'})
    : super(code: 'NOT_FOUND', statusCode: 404);
}

class ValidationException extends ApiException {
  ValidationException({
    super.message = 'Validation error',
    super.details,
    super.code = 'VALIDATION_ERROR',
  }) : super(statusCode: 400);
}

class ServerException extends ApiException {
  ServerException({super.message = 'Internal server error'})
    : super(code: 'SERVER_ERROR', statusCode: 500);
}

class TokenExpiredException extends ApiException {
  TokenExpiredException({super.message = 'Token expired'})
    : super(code: 'TOKEN_EXPIRED', statusCode: 401);
}
