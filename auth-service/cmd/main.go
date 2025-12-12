package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/casadeprovision2016/cotai/auth-service/internal/config"
	"github.com/casadeprovision2016/cotai/auth-service/internal/handlers"
	"github.com/casadeprovision2016/cotai/auth-service/internal/logger"
	"github.com/casadeprovision2016/cotai/auth-service/internal/observability"
	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	"google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/reflection"
)

func main() {
	// Load configuration from environment
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load configuration: %v\n", err)
		os.Exit(1)
	}

	// Initialize logger (12-Factor: logs to stdout)
	log := logger.NewLogger(cfg.LogLevel, cfg.LogFormat)
	log.WithFields(logrus.Fields{
		"service":     cfg.ServiceName,
		"environment": cfg.Environment,
		"port":        cfg.Port,
	}).Info("Starting service")

	// Initialize observability (tracing, metrics)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Initialize tracer provider
	_, err = observability.TracerProvider(ctx, cfg.ServiceName, log)
	if err != nil {
		log.WithError(err).Fatal("Failed to initialize tracer provider")
	}

	// Initialize meter provider (Prometheus metrics)
	_, err = observability.MeterProvider(ctx, cfg.ServiceName, log)
	if err != nil {
		log.WithError(err).Fatal("Failed to initialize meter provider")
	}

	// Start Prometheus metrics server
	err = observability.StartPrometheusMetricsServer(cfg.PrometheusPort, log)
	if err != nil {
		log.WithError(err).Fatal("Failed to start Prometheus metrics server")
	}

	// Create gRPC server with OTel instrumentation
	grpcServer := grpc.NewServer(
		grpc.UnaryInterceptor(observability.GRPCUnaryInterceptor()),
		grpc.StreamInterceptor(observability.GRPCStreamInterceptor()),
	)

	// Register health check service
	_ = handlers.NewHealthHandler(log)
	healthServer := health.NewServer()
	grpc_health_v1.RegisterHealthServer(grpcServer, healthServer)

	// Register reflection service (for development/debugging)
	reflection.Register(grpcServer)

	// Set service status to SERVING
	healthServer.SetServingStatus(cfg.ServiceName, grpc_health_v1.HealthCheckResponse_SERVING)

	// Listen on TCP port
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", cfg.Port))
	if err != nil {
		log.WithError(err).Fatal("Failed to listen on port")
	}
	defer listener.Close()

	log.WithField("port", cfg.Port).Info("gRPC server listening")

	// Graceful shutdown handling
	shutdownChan := make(chan os.Signal, 1)
	signal.Notify(shutdownChan, syscall.SIGINT, syscall.SIGTERM)

	// Start server in goroutine
	go func() {
		if err := grpcServer.Serve(listener); err != nil {
			log.WithError(err).Fatal("Server error")
		}
	}()

	// Wait for shutdown signal
	sig := <-shutdownChan
	log.WithField("signal", sig).Info("Shutdown signal received")

	// Graceful shutdown: stop accepting new connections and wait for existing ones
	grpcServer.GracefulStop()
	log.Info("Service stopped gracefully")
}
