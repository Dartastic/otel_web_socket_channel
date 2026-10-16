<!-- dartastic-header:start -->
# OpenTelemetry instrumentation for `web_socket_channel`

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenTelemetry Specification](https://img.shields.io/badge/OpenTelemetry-Specification-blueviolet)](https://opentelemetry.io/docs/specs/otel/)

`otel_web_socket_channel` is an [OpenTelemetry](https://opentelemetry.io/) instrumentation for `web_socket_channel` that
easily adds standard observability to applications that use `web_socket_channel`.  This package depends on 
[dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api).

This package can be used with any OTel backend because it's compliant with the OpenTelemetry Specification.

This package supports Android, iOS, Linux, macOS, Web and Windows, for versions of `web_socket_channel` that support those platforms. It is WASM-ready.

This Apache-2.0 package is professionally maintained and supported with 💙 by Michael Bushe,
Dart and Flutter Maintainer at OpenTelemetry and the creator of [dartastic_opentelemetry](https://pub.dev/packages/dartastic_opentelemetry)
and [dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api). This package is professionally supported by
[Dartastic.io](https://dartastic.io).

---
## Dartastic.io: AI Code Healing and Real User Monitoring for Flutter

**See what your users experience. Find problems with Flutter apps in production. Fix them with AI.**

[Dartastic.io](https://dartastic.io) brings AI code healing, real user monitoring, and OpenTelemetry observability together in one platform built for Dart and Flutter. (Patents pending)

![Dartastic AI answering "Why did crashes jump after the last release?" over a Flutter App Health dashboard](https://dartastic.io/img/pub-dev/HomePageCrashesQuestion.png)

### Dartastic AI — From Production Problems to Code Fixes

Dartastic AI analyzes production telemetry alongside your application source code to diagnose problems and propose fixes.

- **Investigate production issues** using crashes, errors, traces, metrics, and real user telemetry.
- **Find the offending code** by connecting observed problems with your application's source in Dartastic Pub or your source code repos.
- **Generate code patches** that address the underlying problems.
- **Create actionable issues** in your issue tracker, complete with findings and the proposed code patch.

### Dartastic RUM — See What Your Users See

Understand how people actually experience your Flutter application.

- **Replay user sessions** in the Dartastic Observatory session player.
- **Choose your replay fidelity**, from privacy-preserving widget outlines to pixel-level reproductions of the user experience.
- **Investigate real user problems** using session replay and production observability data.

![Dartastic RUM Session Replay](https://dartastic.io/img/pub-dev/session-replay.png)

### Dartastic Observatory — Observability Built for Flutter

A complete observability backend where Flutter and Dart are first-class citizens.

- **Flutter-specific dashboards** for application performance, health, and reliability.
- **Alerts and notifications** through email, Slack, and PagerDuty.
- **Dartastic Cloud Observatory** — Start with a 30-day free trial on isolated, shared infrastructure, as low as $39/mo.
- **Dartastic Hosted Observatory** — Run the observability stack in a private managed environment, sized from Mini to Enterprise XL.
- **Dartastic Self-Hosted Observatory** — The whole platform inside your own network. Your keys, your cluster, with nothing leaving your perimeter.

### Dartastic Native OTel Runtime — Native OpenTelemetry Performance

Collect production telemetry without burdening Flutter's main isolate.

- **Native OpenTelemetry runtime** that moves telemetry processing off the main isolate.
- **Native crash reporting** for problems that Dart can't catch.
- **Widget performance diagnostics** to identify janky widgets.
- **On-device PII filtering** before sensitive data leaves your application.
- **Source-level error diagnostics** powered by the Dartastic Symbolizer API.
- **Platform-native metrics** for iOS, Android, and Linux, including iOS MetricKit and Android Vitals.
- **OpenTelemetry compatibility** — Send telemetry to Dartastic Observatory or any OpenTelemetry platform.

### Dartastic Labs — OpenTelemetry Integrations

Instrument more of your application without writing everything yourself.

- **650+ open-source integrations** for Dart and Flutter libraries and services, including Dio, Shelf, Logger, Anthropic, AWS, Azure, and Stripe. Look for otel_* on pub.dev.

### More Dartastic Tools

**[Dartastic Pub](https://dartastic.io/pub)**

A private Dart package registry for sharing packages and plugins with your team, partners, and customers.

**[Dartastic Symbolizer](https://dartastic.io/symbolizer)**

Turn production errors into lines of source code through a web API, while keeping your source code artifacts private.

### Professional Support and Training

Dartastic.io offers commercial support for the open-source `dartastic_opentelemetry` and `dartastic_opentelemetry_api` packages and the complete Dartastic product suite.

- **Professional support** with available around-the-clock coverage and response times under four hours on qualifying plans.
- **OpenTelemetry training** for teams instrumenting Dart, Flutter, mobile, and web applications.

### Open Standards. No Mandatory Backend.

The Dartastic OpenTelemetry API and SDK are open source and standards-based. You can use them independently of Dartastic's commercial services and send telemetry to any compatible OpenTelemetry backend.

Dartastic's commercial products add native performance, advanced diagnostics, session replay, AI-assisted remediation, and managed observability services.

**[Explore Dartastic.io](https://dartastic.io)**

---
<!-- dartastic-header:end -->

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
