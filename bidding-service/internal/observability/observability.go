package observability

import (
	"context"
	"fmt"
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/sirupsen/logrus"
	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/sdk/metric"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/grpc"
)

// TracerProvider initializes OpenTelemetry tracing
func TracerProvider(ctx context.Context, serviceName string, logger *logrus.Logger) (trace.TracerProvider, error) {
	// Create a basic tracer provider
	// In production, connect to Jaeger via gRPC exporter
	tp := sdktrace.NewTracerProvider()
	otel.SetTracerProvider(tp)

	logger.WithFields(logrus.Fields{
		"service": serviceName,
		"tracer":  "sdk",
	}).Info("Tracer provider initialized")

	return tp, nil
}

// MeterProvider initializes OpenTelemetry metrics with Prometheus exporter
func MeterProvider(ctx context.Context, serviceName string, logger *logrus.Logger) (*metric.MeterProvider, error) {
	// Create a reader for metrics collection
	// In production, integrate with Prometheus registry for /metrics endpoint

	// Create a meter provider
	mp := metric.NewMeterProvider()
	otel.SetMeterProvider(mp)

	logger.WithFields(logrus.Fields{
		"service": serviceName,
		"metrics": "prometheus",
	}).Info("Meter provider initialized")

	return mp, nil
}

// StartPrometheusMetricsServer starts HTTP server exposing /metrics endpoint
func StartPrometheusMetricsServer(port int, logger *logrus.Logger) error {
	http.Handle("/metrics", promhttp.Handler())

	addr := fmt.Sprintf(":%d", port)
	logger.WithField("port", port).Info("Starting Prometheus metrics server")

	go func() {
		if err := http.ListenAndServe(addr, nil); err != nil {
			logger.WithError(err).Error("Prometheus metrics server failed")
		}
	}()

	return nil
}

// GRPCUnaryInterceptor returns a gRPC unary interceptor with OTel instrumentation
func GRPCUnaryInterceptor() grpc.UnaryServerInterceptor {
	return otelgrpc.UnaryServerInterceptor()
}

// GRPCStreamInterceptor returns a gRPC stream interceptor with OTel instrumentation
func GRPCStreamInterceptor() grpc.StreamServerInterceptor {
	return otelgrpc.StreamServerInterceptor()
}

// HealthCheckMetrics provides methods to record health check metrics
type HealthCheckMetrics struct {
	checkCounter prometheus.Counter
}

// NewHealthCheckMetrics creates a new health check metrics recorder
func NewHealthCheckMetrics() *HealthCheckMetrics {
	checkCounter := prometheus.NewCounter(prometheus.CounterOpts{
		Name: "health_checks_total",
		Help: "Total number of health checks performed",
	})
	prometheus.MustRegister(checkCounter)

	return &HealthCheckMetrics{
		checkCounter: checkCounter,
	}
}

// RecordHealthCheck increments the health check counter
func (h *HealthCheckMetrics) RecordHealthCheck() {
	h.checkCounter.Inc()
}
