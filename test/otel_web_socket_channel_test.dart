// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_web_socket_channel/otel_web_socket_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;

  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

Map<String, Object> _attrs(Span span) =>
    {for (final a in span.attributes.toList()) a.key: a.value};

/// In-memory WebSocketChannel for tests. Mirrors the surface enough
/// for the wrapper's needs — `ready`, `protocol`, `closeCode`,
/// `closeReason`, `stream`, `sink`. The stream and sink are wired
/// to internal controllers so tests can drive both sides.
class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel({this.protocol, bool readyFails = false}) {
    if (readyFails) {
      _readyCompleter.completeError(StateError('handshake refused'));
    } else {
      _readyCompleter.complete();
    }
  }

  @override
  final String? protocol;
  final _readyCompleter = Completer<void>();
  final _inbound = StreamController<dynamic>();
  int? _closeCode;
  String? _closeReason;
  late final _sink = _FakeWebSocketSink(this);

  void emitInbound(dynamic data) => _inbound.add(data);
  void closeFromServer({int? code, String? reason}) {
    _closeCode = code;
    _closeReason = reason;
    _inbound.close();
  }

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  Stream<dynamic> get stream => _inbound.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink(this._channel);
  final _FakeWebSocketChannel _channel;
  final List<dynamic> sent = [];
  final _done = Completer<void>();

  @override
  void add(dynamic data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await stream.forEach(add);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel._closeCode = closeCode;
    _channel._closeReason = closeReason;
    if (!_channel._inbound.isClosed) await _channel._inbound.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

void main() {
  group('OTelWebSocketChannel', () {
    late _MemorySpanExporter exporter;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'web-socket-otel-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
    });

    tearDown(() async {
      await OTel.shutdown();
      await OTel.reset();
    });

    test('happy path: span has messaging.* + URL + close code', () async {
      final fake = _FakeWebSocketChannel(protocol: 'chat.v1');
      final channel = OTelWebSocketChannel(
        fake,
        url: Uri.parse('wss://example.com:443/feed'),
      );

      // Force the `ready` future's microtask to flush so the
      // protocol attribute is attached before we close.
      await fake.ready;
      await Future<void>.delayed(Duration.zero);

      // Use sink + stream so the wrapper actually wires up.
      channel.sink.add('ping');
      final received = <dynamic>[];
      final sub = channel.stream.listen(received.add);

      fake.emitInbound('pong');
      await Future<void>.delayed(Duration.zero);

      await channel.sink.close(1000, 'normal');
      await sub.cancel();

      expect(received, equals(['pong']));
      expect(fake._sink.sent, equals(['ping']));

      final span = exporter.spans.single;
      expect(span.name, equals('websocket example.com'));
      expect(span.kind, equals(SpanKind.client));

      final attrs = _attrs(span);
      expect(attrs['messaging.system'], equals('websocket'));
      expect(attrs['messaging.websocket.endpoint_kind'], equals('client'));
      expect(attrs['url.full'], equals('wss://example.com:443/feed'));
      expect(attrs['server.address'], equals('example.com'));
      expect(attrs['server.port'], equals(443));
      expect(attrs['messaging.websocket.protocol'], equals('chat.v1'));
      expect(attrs['messaging.websocket.close_code'], equals(1000));
      expect(attrs['messaging.websocket.close_reason'], equals('normal'));
      expect(span.status, isNot(equals(SpanStatusCode.Error)));
    });

    test('server-initiated close ends the span with close attributes',
        () async {
      final fake = _FakeWebSocketChannel();
      final channel = OTelWebSocketChannel(fake, url: Uri.parse('ws://h/'));

      final received = <dynamic>[];
      final sub = channel.stream.listen(received.add);

      fake.closeFromServer(code: 1011, reason: 'server error');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      final span = exporter.spans.single;
      final attrs = _attrs(span);
      expect(attrs['messaging.websocket.close_code'], equals(1011));
      expect(attrs['messaging.websocket.close_reason'], equals('server error'));
    });

    test('handshake failure flips span status to Error', () async {
      final fake = _FakeWebSocketChannel(readyFails: true);
      OTelWebSocketChannel(fake, url: Uri.parse('ws://h/'));

      // The wrapper observes `ready` errors via .then onError; let
      // that microtask run.
      await Future<void>.delayed(Duration.zero);

      final span = exporter.spans.single;
      expect(span.status, equals(SpanStatusCode.Error));
      final attrs = _attrs(span);
      expect(attrs['error.type'], equals('StateError'));
      final events = span.spanEvents ?? [];
      expect(events.any((e) => e.name == 'exception'), isTrue);
    });

    test('recordFrames: true emits child spans for send + receive', () async {
      final fake = _FakeWebSocketChannel();
      final channel = OTelWebSocketChannel(
        fake,
        url: Uri.parse('ws://h/'),
        recordFrames: true,
      );

      channel.sink.add('hello');
      channel.sink.add([1, 2, 3]); // binary frame

      final received = <dynamic>[];
      final sub = channel.stream.listen(received.add);
      fake.emitInbound('world');
      await Future<void>.delayed(Duration.zero);

      await channel.sink.close(1000);
      await sub.cancel();

      final sends =
          exporter.spans.where((s) => s.name == 'websocket.send').toList();
      final receives =
          exporter.spans.where((s) => s.name == 'websocket.receive').toList();

      expect(sends, hasLength(2));
      expect(receives, hasLength(1));

      final textSend = sends.firstWhere(
        (s) => _attrs(s)['messaging.websocket.frame.type'] == 'text',
      );
      expect(_attrs(textSend)['messaging.websocket.frame.size'], equals(5));

      final binarySend = sends.firstWhere(
        (s) => _attrs(s)['messaging.websocket.frame.type'] == 'binary',
      );
      expect(_attrs(binarySend)['messaging.websocket.frame.size'], equals(3));
    });

    test('runWithoutWebSocketInstrumentation skips span creation', () {
      final fake = _FakeWebSocketChannel();
      runWithoutWebSocketInstrumentation(() {
        OTelWebSocketChannel(fake, url: Uri.parse('ws://h/'));
      });

      expect(
        exporter.spans,
        isEmpty,
        reason: 'suppression scope should bypass the wrapper entirely',
      );
    });
  });
}
