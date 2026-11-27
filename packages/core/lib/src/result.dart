// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/src/app_error.dart';

/// Either a value ([Ok]) or a typed [AppError] ([Err]).
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(AppError error) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// The value, or `null` when this is an [Err].
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// The error, or `null` when this is an [Ok].
  AppError? get errorOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final error) => error,
  };

  /// Transforms the value of an [Ok]; an [Err] is passed through.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Result<R>.ok(transform(value)),
    Err<T>(:final error) => Result<R>.err(error),
  };

  /// Folds both cases into a single value.
  R when<R>({
    required R Function(T value) ok,
    required R Function(AppError error) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final error) => err(error),
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final AppError error;

  @override
  bool operator ==(Object other) => other is Err<T> && other.error == error;

  @override
  int get hashCode => Object.hash(Err, error);
}
