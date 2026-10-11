# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0-wip]

### Changed

- Requires `dartastic_opentelemetry_api >=1.0.0-rc.4 <1.0.0-rc.5`.
- **Breaking:** depends on `dartastic_opentelemetry_api` only, no
  longer on the SDK. The application chooses and initializes the
  OpenTelemetry SDK. Parameters and fields typed with SDK classes
  now use the API types (`APITracer`, `APISpan`, `APILogger`, ...);
  SDK instances are still accepted wherever an API type is expected.

## [0.1.0] - 2026-08-10

### Added

- `OTelWebSocketChannel` — wraps any `WebSocketChannel` and opens
  a single connection-lifetime `CLIENT` span. Sets
  `messaging.system=websocket`, `url.*` / `server.*` info, the
  negotiated subprotocol, and close-code / close-reason on the
  way out.
- Connection-failure path: if the inner channel's `ready` future
  errors, the span is flipped to Error via
  `recordException` + `setStatus(Error)` in OTel-spec order.
- Stream-error path: an error on the inbound stream also marks the
  span Error and surfaces `error.type`.
- `OTelWebSocketChannel.connect(uri)` factory: convenience that
  calls `WebSocketChannel.connect` and wraps the result.
- Per-frame events (opt-in via `recordFrames: true`): each
  `sink.add` and inbound message emits a `websocket.send` /
  `websocket.receive` child span carrying frame type and size.
- `WebSocketSemantics` — typed attribute-key enum implementing
  `OTelSemantic`, package-local pending the upstream OTel
  messaging-spec websocket sub-spec.
- `runWithoutWebSocketInstrumentation` /
  `runWithoutWebSocketInstrumentationAsync` — zone-scoped
  suppression helpers, mirroring `dartastic_grpc_otel` and
  `dartastic_http_otel`. Preemptive: the dartastic SDK doesn't
  use websockets for export today, but log streaming over
  websockets is a plausible future and the recursion shape would
  be identical.
- 5 unit tests pin: happy path with full attribute set + close
  codes, server-initiated close, handshake failure, per-frame
  spans (both text + binary), and the suppression scope.
