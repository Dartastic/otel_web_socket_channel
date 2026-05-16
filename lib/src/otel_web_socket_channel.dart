// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'web_socket_semantics.dart';
import 'web_socket_suppression.dart';

/// OpenTelemetry instrumentation for `package:web_socket_channel`.
///
/// Wraps any [WebSocketChannel] and opens a single connection-lifetime
/// `CLIENT` span. The span ends when the underlying stream is done,
/// the sink is closed, or a fatal error reaches the channel. Per the
/// OTel messaging semantic-convention proposal, this is the
/// "session" model — one span per WebSocket connection, optionally
/// with per-frame child spans for high-cardinality apps that need it.
///
/// ```dart
/// final raw = WebSocketChannel.connect(Uri.parse('wss://example.com/feed'));
/// final channel = OTelWebSocketChannel(raw, url: Uri.parse('wss://example.com/feed'));
///
/// channel.sink.add('hello');
/// channel.stream.listen(handleFrame);
/// // ... later
/// await channel.sink.close(1000, 'normal');
/// ```
///
/// ## Span shape
///
/// | Attribute | Source | When set |
/// |---|---|---|
/// | `messaging.system` | constant `websocket` | always |
/// | `messaging.websocket.endpoint_kind` | constant `client` | always |
/// | `url.full` | `url` constructor arg | when provided |
/// | `server.address` / `server.port` | parsed from `url` | when present |
/// | `messaging.websocket.protocol` | `WebSocketChannel.protocol` | once `ready` resolves |
/// | `messaging.websocket.close_code` | `WebSocketChannel.closeCode` | on connection close |
/// | `messaging.websocket.close_reason` | `WebSocketChannel.closeReason` | on connection close |
///
/// - **Span name**: `websocket <host>` (e.g. `websocket example.com`),
///   or just `websocket` if no URL was provided.
/// - **Span kind**: `CLIENT`.
/// - **Span status**: `Error` if `ready` errors or the stream errors;
///   otherwise unset.
///
/// ## Per-frame events
///
/// Off by default to keep traces cheap. When `recordFrames: true`,
/// each send and each inbound message emits a short child span
/// (`websocket.send` / `websocket.receive`) parented to the
/// connection span, carrying frame type and size attributes. Useful
/// during development but typically too noisy for production.
class OTelWebSocketChannel
    with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  /// Wraps an existing [WebSocketChannel] with OTel instrumentation.
  ///
  /// - [url] — the URL the channel connected to. Used only for span
  ///   attributes (`url.full`, `server.address`, `server.port`);
  ///   pass it when you have it.
  /// - [tracer] — defaults to
  ///   `OTel.tracerProvider().getTracer('otel_web_socket_channel')`.
  /// - [recordFrames] — when `true`, emit per-frame child spans on
  ///   every send and receive. Off by default.
  OTelWebSocketChannel(
    this._inner, {
    Uri? url,
    Tracer? tracer,
    this.recordFrames = false,
  })  : _suppressed = webSocketInstrumentationSuppressed(),
        _tracer = tracer ??
            OTel.tracerProvider().getTracer(
              'otel_web_socket_channel',
            ) {
    if (_suppressed) return;
    final attrs = <String, Object>{
      Messaging.messagingSystem.key: 'websocket',
      WebSocketSemantics.endpointKind.key: 'client',
    };
    if (url != null) {
      attrs[Url.urlFull.key] = url.toString();
      if (url.host.isNotEmpty) {
        attrs[ServerResource.serverAddress.key] = url.host;
      }
      if (url.hasPort) attrs[ServerResource.serverPort.key] = url.port;
    }
    _span = _tracer.startSpan(
      url == null ? 'websocket' : 'websocket ${url.host}',
      kind: SpanKind.client,
      attributes: OTel.attributesFromMap(attrs),
    );

    // Watch for connection success/failure. Surface the negotiated
    // subprotocol on success; flip the span to Error on failure.
    _inner.ready.then(
      (_) {
        final p = _inner.protocol;
        if (p != null && p.isNotEmpty) {
          _span!.addAttributes(OTel.attributes([
            OTel.attributeString(WebSocketSemantics.protocol.key, p),
          ]));
        }
      },
      onError: (Object e, StackTrace st) {
        _setError(e, st);
        _endSpan();
      },
    );
  }

  /// Connects to [url] via [WebSocketChannel.connect] and wraps the
  /// returned channel with OTel instrumentation in one step.
  factory OTelWebSocketChannel.connect(
    Uri url, {
    Iterable<String>? protocols,
    Tracer? tracer,
    bool recordFrames = false,
  }) {
    final inner = WebSocketChannel.connect(url, protocols: protocols);
    return OTelWebSocketChannel(
      inner,
      url: url,
      tracer: tracer,
      recordFrames: recordFrames,
    );
  }

  final WebSocketChannel _inner;
  final Tracer _tracer;
  final bool _suppressed;

  /// Whether per-frame child spans are emitted. See class docs.
  final bool recordFrames;

  APISpan? _span;
  bool _ended = false;
  WebSocketSink? _wrappedSink;
  Stream<dynamic>? _wrappedStream;

  @override
  Future<void> get ready => _inner.ready;

  @override
  String? get protocol => _inner.protocol;

  @override
  int? get closeCode => _inner.closeCode;

  @override
  String? get closeReason => _inner.closeReason;

  @override
  Stream<dynamic> get stream {
    if (_suppressed) return _inner.stream;
    return _wrappedStream ??= _inner.stream.transform(
      StreamTransformer<dynamic, dynamic>.fromHandlers(
        handleData: (data, sink) {
          if (recordFrames) _emitFrameEvent('receive', data);
          sink.add(data);
        },
        handleError: (Object error, StackTrace stackTrace, EventSink sink) {
          _setError(error, stackTrace);
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          _endSpan();
          sink.close();
        },
      ),
    );
  }

  @override
  WebSocketSink get sink {
    if (_suppressed) return _inner.sink;
    return _wrappedSink ??= _OTelWebSocketSink(_inner.sink, this);
  }

  /// Ends the connection span. [closeCode] / [closeReason] override
  /// the inner channel's getters when known — that matters for the
  /// user-initiated close path, where the user passes the codes to
  /// the sink before the inner channel has had a chance to record
  /// them on itself.
  void _endSpan({int? closeCode, String? closeReason}) {
    if (_ended || _suppressed) return;
    _ended = true;
    final attrs = <Attribute<Object>>[];
    final code = closeCode ?? _inner.closeCode;
    if (code != null) {
      attrs.add(OTel.attributeInt(WebSocketSemantics.closeCode.key, code));
    }
    final reason = closeReason ?? _inner.closeReason;
    if (reason != null && reason.isNotEmpty) {
      attrs.add(
        OTel.attributeString(WebSocketSemantics.closeReason.key, reason),
      );
    }
    if (attrs.isNotEmpty) _span!.addAttributes(OTel.attributes(attrs));
    _span!.end();
  }

  void _setError(Object error, StackTrace stackTrace) {
    if (_ended || _suppressed) return;
    _span!.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        error.runtimeType.toString(),
      ),
    ]));
    // Spec order: recordException first, THEN setStatus.
    _span!.recordException(error, stackTrace: stackTrace);
    _span!.setStatus(SpanStatusCode.Error, error.toString());
  }

  void _emitFrameEvent(String operation, dynamic frame) {
    if (_span == null) return;
    final size = _frameSize(frame);
    final type = frame is String ? 'text' : 'binary';
    final span = _tracer.startSpan(
      'websocket.$operation',
      parentSpan: _span,
      attributes: OTel.attributesFromMap(<String, Object>{
        WebSocketSemantics.operation.key: operation,
        WebSocketSemantics.frameType.key: type,
        if (size != null) WebSocketSemantics.frameSize.key: size,
      }),
    );
    span.end();
  }

  int? _frameSize(dynamic frame) {
    if (frame is String) return frame.length;
    if (frame is List<int>) return frame.length;
    return null;
  }
}

class _OTelWebSocketSink implements WebSocketSink {
  _OTelWebSocketSink(this._inner, this._owner);
  final WebSocketSink _inner;
  final OTelWebSocketChannel _owner;

  @override
  void add(dynamic data) {
    if (_owner.recordFrames) _owner._emitFrameEvent('send', data);
    _inner.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _owner._setError(error, stackTrace ?? StackTrace.current);
    _inner.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) => _inner.addStream(stream);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _owner._endSpan(closeCode: closeCode, closeReason: closeReason);
    await _inner.close(closeCode, closeReason);
  }

  @override
  Future<void> get done => _inner.done;
}
