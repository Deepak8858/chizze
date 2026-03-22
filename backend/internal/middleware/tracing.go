package middleware

import (
	"context"
	"fmt"
	"os"

	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"

	"github.com/gin-gonic/gin"
)

// TracerProvider holds the configured trace provider for shutdown
var tracerProvider *sdktrace.TracerProvider

// InitTracing sets up OpenTelemetry distributed tracing.
// If OTEL_EXPORTER_OTLP_ENDPOINT env is set, traces go to the OTLP collector.
// Otherwise, traces go to stdout (dev mode).
func InitTracing(ctx context.Context, serviceName, version string) (func(context.Context) error, error) {
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String(serviceName),
			semconv.ServiceVersionKey.String(version),
			semconv.DeploymentEnvironmentKey.String(os.Getenv("GIN_MODE")),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("create otel resource: %w", err)
	}

	var exporter sdktrace.SpanExporter

	otlpEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if otlpEndpoint != "" {
		// Production: send to OTLP collector (Jaeger, Grafana Tempo, etc.)
		opts := []otlptracehttp.Option{
			otlptracehttp.WithEndpoint(otlpEndpoint),
		}
		// Allow insecure for local collectors
		if os.Getenv("OTEL_EXPORTER_OTLP_INSECURE") == "true" {
			opts = append(opts, otlptracehttp.WithInsecure())
		}
		exporter, err = otlptracehttp.New(ctx, opts...)
		if err != nil {
			return nil, fmt.Errorf("create OTLP exporter: %w", err)
		}
		fmt.Printf("[tracing] OTLP exporter → %s\n", otlpEndpoint)
	} else if os.Getenv("GIN_MODE") == "release" {
		// Production without OTLP collector: use noop (no stdout spam)
		// Previously this dumped 50-line JSON spans to docker logs on every request
		fmt.Println("[tracing] Production mode — no OTLP endpoint set, tracing disabled")
		// Return early with a noop shutdown — no exporter, no TracerProvider
		return func(_ context.Context) error { return nil }, nil
	} else {
		// Dev: print spans to stdout
		exporter, err = stdouttrace.New(stdouttrace.WithPrettyPrint())
		if err != nil {
			return nil, fmt.Errorf("create stdout exporter: %w", err)
		}
		fmt.Println("[tracing] stdout exporter (set OTEL_EXPORTER_OTLP_ENDPOINT for production)")
	}

	// Sample 10% in production, 100% in dev
	var sampler sdktrace.Sampler
	if os.Getenv("GIN_MODE") == "release" {
		sampler = sdktrace.ParentBased(sdktrace.TraceIDRatioBased(0.1))
	} else {
		sampler = sdktrace.AlwaysSample()
	}

	tracerProvider = sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sampler),
	)

	otel.SetTracerProvider(tracerProvider)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return tracerProvider.Shutdown, nil
}

// OtelGin returns the OpenTelemetry Gin middleware for automatic request tracing
func OtelGin(serviceName string) gin.HandlerFunc {
	return otelgin.Middleware(serviceName)
}
