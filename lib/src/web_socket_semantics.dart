// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

/// WebSocket-specific attribute keys that aren't in the upstream
/// API's `Messaging` enum yet.
///
/// Use the API's [Messaging.messagingSystem] for `messaging.system`
/// (we always set it to `websocket`); this enum covers the
/// websocket-specific keys (close code, close reason, frame size,
/// frame type) and the WebSocket-flavored operation strings.
///
/// Tracks the OTel messaging semantic convention's websocket
/// sub-spec, which is still draft. When the API enum catches up,
/// these can `@Deprecated`-pivot.
enum WebSocketSemantics implements OTelSemantic {
  /// Which side of the connection. `client` or `server`.
  endpointKind('messaging.websocket.endpoint_kind'),

  /// Numeric close code per RFC 6455 §7.4.1. Set on connection-end
  /// spans when the channel closed with a known code.
  closeCode('messaging.websocket.close_code'),

  /// Textual close reason if the peer sent one.
  closeReason('messaging.websocket.close_reason'),

  /// The negotiated subprotocol, if any.
  protocol('messaging.websocket.protocol'),

  /// `send` or `receive`. Set on per-frame event spans when
  /// `recordFrames: true`.
  operation('messaging.websocket.operation'),

  /// Size of the frame payload in bytes. Set on per-frame event
  /// spans.
  frameSize('messaging.websocket.frame.size'),

  /// `text` or `binary`. Set on per-frame event spans.
  frameType('messaging.websocket.frame.type');

  const WebSocketSemantics(this.key);

  @override
  final String key;

  @override
  String toString() => key;
}
