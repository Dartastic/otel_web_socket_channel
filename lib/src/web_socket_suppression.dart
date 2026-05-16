// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

/// Zone key used to mark a region of code as "do not instrument
/// with the WebSocket wrapper." `Symbol`-keyed so collisions can't
/// happen and the value doesn't cross isolate boundaries.
const Symbol _suppressKey = #otel_web_socket_channel_suppress;

/// Returns `true` when the current zone has opted out of WebSocket
/// OTel instrumentation.
///
/// `OTelWebSocketChannel` consults this when deciding whether to
/// open a span for the connection or wrap the sink / stream.
bool webSocketInstrumentationSuppressed() {
  return Zone.current[_suppressKey] == true;
}

/// Runs [body] in a zone where any [OTelWebSocketChannel] constructed
/// inside it will pass through without span creation.
///
/// `package:web_socket_channel` is a likely future transport for
/// OTel log streaming; this helper exists to prevent recursion when
/// that lands, matching the pattern used by `otel_grpc`
/// and `otel_http`. The current dartastic SDK does not
/// use websockets for export, so this is preemptive defense.
T runWithoutWebSocketInstrumentation<T>(T Function() body) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}

/// Async variant of [runWithoutWebSocketInstrumentation]. Both forms
/// are safe to nest; they no-op once already inside a suppressed
/// zone.
Future<T> runWithoutWebSocketInstrumentationAsync<T>(
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}
