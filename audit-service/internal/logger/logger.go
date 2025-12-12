package logger

import (
	"os"

	"github.com/sirupsen/logrus"
)

// NewLogger creates a structured JSON logger configured for production use
func NewLogger(logLevel, logFormat string) *logrus.Logger {
	logger := logrus.New()

	// Set output to stdout (12-Factor app principle)
	logger.SetOutput(os.Stdout)

	// Parse and set log level
	level, err := logrus.ParseLevel(logLevel)
	if err != nil {
		level = logrus.InfoLevel
	}
	logger.SetLevel(level)

	// Set formatter based on configuration
	if logFormat == "json" {
		logger.SetFormatter(&logrus.JSONFormatter{
			TimestampFormat: "2006-01-02T15:04:05.000Z07:00",
			FieldMap: logrus.FieldMap{
				logrus.FieldKeyTime:  "timestamp",
				logrus.FieldKeyLevel: "level",
				logrus.FieldKeyMsg:   "message",
			},
		})
	} else {
		logger.SetFormatter(&logrus.TextFormatter{
			TimestampFormat: "2006-01-02T15:04:05Z",
			FullTimestamp:   true,
		})
	}

	return logger
}

// WithContext returns a logger entry with correlation context
func WithContext(logger *logrus.Logger, fields map[string]interface{}) *logrus.Entry {
	return logger.WithFields(fields)
}
