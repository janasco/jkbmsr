import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;

/// Turns a caught error into short, plain-language text that's safe to show
/// a user -- never the raw exception toString(), which leaks internals like
/// `PlatformException(network_error, x2.d: 7: , null, null)` or
/// `ClientException with SocketConnection failed (OS Error: No route to
/// host, errno = 113), address = api.jkbmsr.com, port = 443, uri=...`
/// (both seen live on the login screen, 2026-08-22).
///
/// Deliberate app-level exceptions (api_client.dart throws `Exception(msg)`
/// with a clean, already-user-facing message pulled from the API's JSON
/// error body) still pass straight through by stripping Dart's own
/// "Exception: " prefix -- this only replaces genuinely raw/technical
/// errors: network failures below the API layer, and native platform
/// exceptions from things like Google Sign-In.
String friendlyErrorMessage(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  if (error is SocketException || error is http.ClientException || error is HttpException) {
    return "Can't reach JKBMSR Cloud. Check your internet connection and try again.";
  }
  if (error is TimeoutException) {
    return 'That took too long. Check your connection and try again.';
  }
  if (error is PlatformException) {
    if (error.code == 'network_error') {
      return "Can't reach Google. Check your internet connection and try again.";
    }
    if (error.code == 'sign_in_canceled' || error.code == 'sign_in_failed') {
      return 'Sign-in was cancelled or failed. Please try again.';
    }
    return 'Sign-in failed. Please try again.';
  }
  if (error is FormatException) {
    return fallback;
  }

  final text = error.toString();
  if (text.startsWith('Exception: ')) {
    final message = text.replaceFirst('Exception: ', '');
    return message.isNotEmpty ? message : fallback;
  }
  return fallback;
}
