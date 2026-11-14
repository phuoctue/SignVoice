import { Request, Response, NextFunction } from 'express';
import { AppError } from '../errors/AppError';
import { ErrorCodes } from '../errors/errorCodes';
import { env } from '../../config/env';
import { Error as MongooseError } from 'mongoose';

/**
 * Global error handler middleware
 * Must be registered LAST in middleware chain
 */
export function errorHandler(
  err: Error & {code?: unknown; statusCode?: unknown; keyPattern?: Record<string, unknown>},
  req: Request,
  res: Response,
  _next: NextFunction
): void {
  void _next; // Express identifies error middleware by its four parameters.
  // Default error response
  let statusCode = 500;
  let errorCode: string = ErrorCodes.INTERNAL_SERVER_ERROR;
  let message = 'An unexpected error occurred';

  // Log error for debugging (but don't expose to client)
  if (env.isDevelopment) {
    console.error('❌ Error:', err);
  } else {
    // In production, log error details to logging service
    console.error('❌ Error:', {
      message: err.message,
      code: err.code,
      statusCode: err.statusCode,
      stack: env.isDevelopment ? err.stack : undefined,
    });
  }

  // Handle known application errors
  if (err instanceof AppError) {
    statusCode = err.statusCode;
    errorCode = err.code;
    message = err.message;
  }
  // Handle Mongoose validation errors
  else if (err instanceof MongooseError.ValidationError) {
    statusCode = 422;
    errorCode = ErrorCodes.VALIDATION_ERROR;
    message = Object.values(err.errors)
      .map(e => e.message)
      .join(', ');
  }
  // Handle Mongoose duplicate key errors
  else if (err.code === 11000) {
    statusCode = 409;
    errorCode = ErrorCodes.CONFLICT;
    const field = Object.keys(err.keyPattern!)[0];
    message = `${field} already exists`;
  }
  // Handle Mongoose cast errors (invalid ObjectId)
  else if (err instanceof MongooseError.CastError) {
    statusCode = 400;
    errorCode = ErrorCodes.BAD_REQUEST;
    message = 'Invalid ID format';
  }
  // Handle JWT errors
  else if (err.name === 'JsonWebTokenError') {
    statusCode = 401;
    errorCode = ErrorCodes.AUTH_TOKEN_INVALID;
    message = 'Invalid token';
  }
  else if (err.name === 'TokenExpiredError') {
    statusCode = 401;
    errorCode = ErrorCodes.AUTH_TOKEN_EXPIRED;
    message = 'Token expired';
  }
  // Handle unexpected errors
  else {
    // Don't expose internal error details to client
    if (!env.isDevelopment) {
      message = 'Internal server error';
    } else {
      message = err.message;
    }
  }

  // Send error response
  res.status(statusCode).json({
    success: false,
    error: {
      code: errorCode,
      message: message,
    },
    ...(env.isDevelopment && { stack: err.stack }),
    requestId: req.id, // Added by request ID middleware
  });
}

/**
 * Handle 404 - Not Found
 * Place this before errorHandler middleware
 */
export function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({
    success: false,
    error: {
      code: ErrorCodes.NOT_FOUND,
      message: `Route ${req.method} ${req.path} not found`,
    },
    requestId: req.id,
  });
}
