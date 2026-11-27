// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';

/// Maps any failure from a Dio call to a typed, secret-free [AppError].
///
/// Errors raised by the secure client (certificate decisions, pin mismatch,
/// cleartext and redirect refusals, size limit) travel in `DioException.error`
/// as an [AppError] and are passed through unchanged. Everything else is
/// classified by Dio's exception type and the HTTP status.
AppError appErrorFromDio(Object error) {
  if (error is AppError) return error;
  if (error is! DioException) {
    return const AppError(ErrorCategory.networkUnreachable);
  }
  final inner = error.error;
  if (inner is AppError) return inner;
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const AppError(ErrorCategory.timeout);
    case DioExceptionType.badCertificate:
      return const AppError(ErrorCategory.tlsUntrusted);
    case DioExceptionType.badResponse:
      return appErrorFromStatus(error.response?.statusCode);
    case DioExceptionType.cancel:
      return const AppError(
        ErrorCategory.networkUnreachable,
        debugDetail: 'cancelled',
      );
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      if (inner is HandshakeException || inner is TlsException) {
        return const AppError(ErrorCategory.tlsUntrusted);
      }
      return const AppError(ErrorCategory.networkUnreachable);
  }
}

/// Maps an HTTP status code to an [AppError] category.
AppError appErrorFromStatus(int? status) {
  if (status == 401 || status == 403) {
    return const AppError(ErrorCategory.authFailed);
  }
  if (status == 404) return const AppError(ErrorCategory.notFound);
  return const AppError(ErrorCategory.serverError);
}
