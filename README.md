# otel_web_socket_channel

OpenTelemetry instrumentation for [`package:web_socket_channel`](https://pub.dev/packages/web_socket_channel),
Dart's canonical WebSocket abstraction. Built on the
[Dartastic OpenTelemetry SDK](https://pub.dev/packages/dartastic_opentelemetry).

Wrap any `WebSocketChannel` and get a single connection-lifetime
`CLIENT` span with `messaging.*` semconv attributes, close codes,
and (opt-in) per-frame child spans.

```dart
final channel = OTelWebSocketChannel.connect(
  Uri.parse('wss://example.com/feed'),
);

channel.sink.add('hello');
channel.stream.listen(handleFrame);
// ...
await channel.sink.close(1000, 'normal');
```

`OTelWebSocketChannel` implements `WebSocketChannel`, so it slots
into anywhere a regular channel is expected.

## ⚠️ Preemptive self-recursion guard

`package:web_socket_channel` isn't a transport the dartastic SDK
uses for OTel export today — but it's a plausible future transport
for log streaming. To stay ahead of that, this package ships the
same suppression pattern as `otel_grpc` and
`otel_http`:

```dart
import 'package:otel_web_socket_channel/otel_web_socket_channel.dart';

await runWithoutWebSocketInstrumentationAsync(() async {
  await myExportChannel.sink.add(...);
});
```

Inside the helper's zone, `OTelWebSocketChannel` becomes a
transparent passthrough — no span, no event. Sync variant:
`runWithoutWebSocketInstrumentation`. Safe to nest.

## Span shape

| Attribute | Source | When set |
|---|---|---|
| `messaging.system` | constant `websocket` | always |
| `messaging.websocket.endpoint_kind` | constant `client` | always |
| `url.full` | `url` constructor arg | when provided |
| `server.address` / `server.port` | parsed from `url` | when present |
| `messaging.websocket.protocol` | `WebSocketChannel.protocol` | once `ready` resolves |
| `messaging.websocket.close_code` | sink-close arg or `closeCode` getter | on connection close |
| `messaging.websocket.close_reason` | sink-close arg or `closeReason` getter | on connection close |
| `error.type` | exception's runtime class | on `ready` error or stream error |

- **Span name**: `websocket <host>` (e.g. `websocket example.com`)
  if a `url` was provided, else just `websocket`.
- **Span kind**: `CLIENT`.
- **Span status**: `Error` if `ready` errors or the stream errors;
  otherwise unset.

## Per-frame events (opt-in)

Off by default — most apps don't want a span per WebSocket frame.
Turn on with `recordFrames: true` for development:

```dart
final channel = OTelWebSocketChannel(
  raw,
  url: url,
  recordFrames: true,
);
```

Each `sink.add(...)` and inbound message emits a short child span:

| Span | Attributes |
|---|---|
| `websocket.send` | `messaging.websocket.operation=send`, `frame.type` (`text`/`binary`), `frame.size` |
| `websocket.receive` | `messaging.websocket.operation=receive`, `frame.type`, `frame.size` |

Both are parented to the connection span. The `frame.size` is the
byte length for binary frames or the character length for text
frames.

## Configuration

| Constructor arg | Default | Effect |
|---|---|---|
| `url` | — | Used for `url.full` / `server.*` span attributes. Pass it when you have it. |
| `tracer` | `OTel.tracerProvider().getTracer('otel_web_socket_channel')` | The tracer that emits the spans. |
| `recordFrames` | `false` | Emit per-frame child spans. See above. |

## Caveats

- Long-lived spans. The connection span lives for the full duration
  of the WebSocket — which can be minutes or hours. Tracing backends
  generally handle long-lived spans, but be aware they typically
  don't appear in search until they end. The OTel messaging-spec
  proposal endorses the "session"-style span for WebSocket-like
  transports.
- The wrapper calls `OTel.tracerProvider().getTracer(...)` in its
  constructor — `OTel.initialize()` must have run first.
- `addStream` is forwarded transparently to the inner sink and
  doesn't currently emit per-frame events even with
  `recordFrames: true`. Use `sink.add` for individual frames if
  you want per-frame visibility.

## License

Apache 2.0 — see `LICENSE`.
