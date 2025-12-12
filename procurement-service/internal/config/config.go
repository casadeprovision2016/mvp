package config

import (
	"fmt"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

// Config holds all application configuration loaded from environment variables
type Config struct {
	// Service identity
	ServiceName string
	Port        int
	Environment string

	// Database
	DatabaseURL      string
	DatabasePoolSize int

	// Cache
	RedisURL string

	// Observability
	JaegerAgentHost string
	JaegerAgentPort int
	PrometheusPort  int

	// Multi-tenancy & Security
	JWTSecret   string
	JWTIssuer   string
	JWTAudience string

	// Logging
	LogLevel  string
	LogFormat string

	// Feature Flags
	RLSEnabled   bool
	AuditEnabled bool
}

// Load loads configuration from environment variables and .env file
func Load() (*Config, error) {
	// Load .env file if it exists (non-blocking)
	_ = godotenv.Load()

	cfg := &Config{
		ServiceName:      getEnvString("SERVICE_NAME", "auth-service"),
		Port:             getEnvInt("PORT", 50051),
		Environment:      getEnvString("ENVIRONMENT", "development"),
		DatabaseURL:      getEnvString("DATABASE_URL", "postgresql://user:password@localhost:5432/cotai"),
		DatabasePoolSize: getEnvInt("DATABASE_POOL_SIZE", 20),
		RedisURL:         getEnvString("REDIS_URL", "redis://localhost:6379/0"),
		JaegerAgentHost:  getEnvString("JAEGER_AGENT_HOST", "localhost"),
		JaegerAgentPort:  getEnvInt("JAEGER_AGENT_PORT", 6831),
		PrometheusPort:   getEnvInt("PROMETHEUS_PORT", 8090),
		JWTSecret:        getEnvString("JWT_SECRET", "your-secret-key-change-in-production"),
		JWTIssuer:        getEnvString("JWT_ISSUER", "https://auth.cotai.local"),
		JWTAudience:      getEnvString("JWT_AUDIENCE", "auth-service"),
		LogLevel:         getEnvString("LOG_LEVEL", "info"),
		LogFormat:        getEnvString("LOG_FORMAT", "json"),
		RLSEnabled:       getEnvBool("FEATURE_RLS_ENABLED", true),
		AuditEnabled:     getEnvBool("FEATURE_AUDIT_ENABLED", true),
	}

	// Validate critical config
	if cfg.JWTSecret == "your-secret-key-change-in-production" && cfg.Environment == "production" {
		return nil, fmt.Errorf("JWT_SECRET must be set for production")
	}

	return cfg, nil
}

// Helper functions to read environment variables with type conversion

func getEnvString(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value, exists := os.LookupEnv(key); exists {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
	if value, exists := os.LookupEnv(key); exists {
		return value == "true" || value == "1" || value == "yes"
	}
	return defaultValue
}
