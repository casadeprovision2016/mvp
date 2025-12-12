package logger

import (
	"bytes"
	"testing"

	log "github.com/sirupsen/logrus"
)

func TestNewLogger(t *testing.T) {
	tests := []struct {
		name      string
		logLevel  string
		logFormat string
		wantLevel log.Level
	}{
		{
			name:      "debug level",
			logLevel:  "debug",
			logFormat: "json",
			wantLevel: log.DebugLevel,
		},
		{
			name:      "info level",
			logLevel:  "info",
			logFormat: "json",
			wantLevel: log.InfoLevel,
		},
		{
			name:      "warn level",
			logLevel:  "warn",
			logFormat: "json",
			wantLevel: log.WarnLevel,
		},
		{
			name:      "error level",
			logLevel:  "error",
			logFormat: "text",
			wantLevel: log.ErrorLevel,
		},
		{
			name:      "invalid level defaults to info",
			logLevel:  "invalid",
			logFormat: "json",
			wantLevel: log.InfoLevel,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			logger := NewLogger(tt.logLevel, tt.logFormat)

			if logger == nil {
				t.Errorf("NewLogger() returned nil")
				return
			}

			if logger.Level != tt.wantLevel {
				t.Errorf("NewLogger() level = %v, want %v", logger.Level, tt.wantLevel)
			}
		})
	}
}

func TestLoggerJSONFormat(t *testing.T) {
	var buf bytes.Buffer
	logger := NewLogger("info", "json")
	logger.SetOutput(&buf)

	logger.WithFields(log.Fields{"user_id": 123, "action": "login"}).
		Info("User logged in")

	output := buf.String()
	if output == "" {
		t.Error("Logger produced no output")
	}

	// Check for JSON-like structure
	if !bytes.ContainsAny([]byte(output), `{}`) {
		t.Errorf("Logger output does not appear to be JSON: %s", output)
	}
}

func TestLoggerTextFormat(t *testing.T) {
	var buf bytes.Buffer
	logger := NewLogger("info", "text")
	logger.SetOutput(&buf)

	logger.Info("Test message")

	output := buf.String()
	if output == "" {
		t.Error("Logger produced no output")
	}

	if !bytes.Contains([]byte(output), []byte("Test message")) {
		t.Errorf("Logger output does not contain message: %s", output)
	}
}
