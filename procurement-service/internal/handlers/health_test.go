package handlers

import (
	"context"
	"testing"

	"github.com/sirupsen/logrus"
	"google.golang.org/protobuf/types/known/emptypb"
)

func TestHealthCheck(t *testing.T) {
	logger := logrus.New()
	handler := NewHealthHandler(logger)

	resp, err := handler.Check(context.Background(), &emptypb.Empty{})

	if err != nil {
		t.Errorf("Check() returned error: %v", err)
		return
	}

	if resp == nil {
		t.Errorf("Check() returned nil response")
	}
}

func TestHealthWatch(t *testing.T) {
	logger := logrus.New()
	handler := NewHealthHandler(logger)

	err := handler.Watch(context.Background(), &emptypb.Empty{})

	// Watch should return Unimplemented status
	if err == nil {
		t.Error("Watch() expected error, got nil")
	}
}
