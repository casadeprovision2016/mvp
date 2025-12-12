package handlers

import (
	"context"

	"github.com/sirupsen/logrus"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"
)

// HealthHandler implements health check services
type HealthHandler struct {
	logger *logrus.Logger
}

// NewHealthHandler creates a new health check handler
func NewHealthHandler(logger *logrus.Logger) *HealthHandler {
	return &HealthHandler{
		logger: logger,
	}
}

// Check performs a readiness check (implements gRPC health check interface)
func (h *HealthHandler) Check(ctx context.Context, _ *emptypb.Empty) (*emptypb.Empty, error) {
	h.logger.WithField("endpoint", "/health/check").Debug("Health check requested")
	return &emptypb.Empty{}, nil
}

// Watch streams health status (not implemented for now)
func (h *HealthHandler) Watch(ctx context.Context, _ *emptypb.Empty) error {
	h.logger.WithField("endpoint", "/health/watch").Debug("Health watch requested")
	return status.Error(codes.Unimplemented, "watch not implemented")
}
