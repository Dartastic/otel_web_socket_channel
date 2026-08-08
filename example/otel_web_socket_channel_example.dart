// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

// A minimal WebSocket client with OpenTelemetry instrumentation:
// one connection-lifetime CLIENT span with messaging.* semconv
// attributes and close codes, plus opt-in per-frame child spans.
//
// Point it at any echo server you control, then watch the spans
// arrive at your OTLP endpoint.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_web_socket_channel/otel_web_socket_channel.dart';

Future<void> main() async {
  // Configure exporters/endpoint via the standard OTEL_* environment
  // variables (e.g. OTEL_EXPORTER_OTLP_ENDPOINT).
  await OTel.initialize(serviceName: 'otel-web-socket-channel-example');

  final url = Uri.parse('wss://echo.websocket.org');

  // Connect and wrap in one step. The span opens now and carries
  // url.full / server.address / server.port from the URL.
  final channel = OTelWebSocketChannel.connect(url);
  await channel.ready;

  channel.sink.add('hello');
  final echoed = await channel.stream.first;
  print('echoed: $echoed');

  // Ends the connection span, recording the close code and reason as
  // messaging.websocket.close_code / close_reason attributes.
  await channel.sink.close(1000, 'normal');
}
