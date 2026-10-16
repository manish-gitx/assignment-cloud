import os

from opentelemetry import trace

ENDPOINT = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "")


def setup(app):
    if ENDPOINT == "":
        return

    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.flask import FlaskInstrumentor

    service = os.environ.get("OTEL_SERVICE_NAME", "temp-converter")
    provider = TracerProvider(resource=Resource.create({"service.name": service}))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)

    FlaskInstrumentor().instrument_app(app, excluded_urls="healthz,readyz,metrics")


def current_trace_id():
    span = trace.get_current_span()
    ctx = span.get_span_context()
    if not ctx.is_valid:
        return ""
    return format(ctx.trace_id, "032x")
