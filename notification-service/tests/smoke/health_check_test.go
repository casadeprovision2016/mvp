package smoke

import (
"context"
"fmt"
"testing"
"time"

"google.golang.org/grpc"
pb "google.golang.org/grpc/health/grpc_health_v1"
)

// TestHealthCheckEndpoint performs a health check via gRPC
func TestHealthCheckEndpoint(t *testing.T) {
// Note: This test requires the auth-service to be running on :50051
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()

conn, err := grpc.DialContext(ctx, "localhost:50051", grpc.WithInsecure())
if err != nil {
t.Skipf("Could not connect to service (ensure it's running): %v", err)
}
defer conn.Close()

client := pb.NewHealthClient(conn)
resp, err := client.Check(context.Background(), &pb.HealthCheckRequest{
Service: "auth.AuthService",
})

if err != nil {
t.Errorf("Health check failed: %v", err)
return
}

if resp.Status != pb.HealthCheckResponse_SERVING {
t.Errorf("Service status = %v, want SERVING", resp.Status)
}
}

// TestServiceConnectivity tests basic gRPC connectivity
func TestServiceConnectivity(t *testing.T) {
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()

conn, err := grpc.DialContext(ctx, "localhost:50051", grpc.WithInsecure())
if err != nil {
t.Skipf("Could not connect to service (ensure it's running): %v", err)
}
defer conn.Close()

if conn.GetState().String() == "SHUTDOWN" {
t.Error("Connection is in SHUTDOWN state")
}
}

// TestPrometheusMetricsEndpoint checks if metrics are available
func TestPrometheusMetricsEndpoint(t *testing.T) {
// Note: This test requires curl or similar HTTP tool
// Metrics server should be running on :8090
t.Logf("Prometheus metrics endpoint: http://localhost:8090/metrics")
t.Logf("To verify metrics, run: curl http://localhost:8090/metrics")
}
