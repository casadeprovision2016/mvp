package config

import (
"os"
"testing"
)

func TestLoad(t *testing.T) {
tests := []struct {
name    string
setup   func()
cleanup func()
wantErr bool
}{
{
name: "load with defaults",
setup: func() {
os.Clearenv()
},
cleanup: func() {
os.Clearenv()
},
wantErr: false,
},
{
name: "load with custom env vars",
setup: func() {
os.Clearenv()
os.Setenv("SERVICE_NAME", "test-service")
os.Setenv("PORT", "9999")
os.Setenv("LOG_LEVEL", "debug")
},
cleanup: func() {
os.Clearenv()
},
wantErr: false,
},
{
name: "production mode with default JWT secret fails",
setup: func() {
os.Clearenv()
os.Setenv("ENVIRONMENT", "production")
},
cleanup: func() {
os.Clearenv()
},
wantErr: true,
},
{
name: "production mode with custom JWT secret succeeds",
setup: func() {
os.Clearenv()
os.Setenv("ENVIRONMENT", "production")
os.Setenv("JWT_SECRET", "super-secret-key")
},
cleanup: func() {
os.Clearenv()
},
wantErr: false,
},
}

for _, tt := range tests {
t.Run(tt.name, func(t *testing.T) {
tt.setup()
defer tt.cleanup()

got, err := Load()

if (err != nil) != tt.wantErr {
t.Errorf("Load() error = %v, wantErr %v", err, tt.wantErr)
return
}

if !tt.wantErr && got == nil {
t.Errorf("Load() returned nil config when error was not expected")
}
})
}
}

func TestGetEnvString(t *testing.T) {
tests := []struct {
name     string
key      string
defValue string
setup    func()
cleanup  func()
want     string
}{
{
name:     "env var exists",
key:      "TEST_VAR",
defValue: "default",
setup: func() {
os.Setenv("TEST_VAR", "custom")
},
cleanup: func() {
os.Unsetenv("TEST_VAR")
},
want: "custom",
},
{
name:     "env var not set",
key:      "NONEXISTENT_VAR",
defValue: "default",
setup:    func() {},
cleanup:  func() {},
want:     "default",
},
}

for _, tt := range tests {
t.Run(tt.name, func(t *testing.T) {
tt.setup()
defer tt.cleanup()

got := getEnvString(tt.key, tt.defValue)
if got != tt.want {
t.Errorf("getEnvString() = %v, want %v", got, tt.want)
}
})
}
}

func TestGetEnvInt(t *testing.T) {
tests := []struct {
name     string
key      string
defValue int
setup    func()
cleanup  func()
want     int
}{
{
name:     "valid int",
key:      "TEST_INT",
defValue: 100,
setup: func() {
os.Setenv("TEST_INT", "999")
},
cleanup: func() {
os.Unsetenv("TEST_INT")
},
want: 999,
},
{
name:     "invalid int, return default",
key:      "TEST_INT_BAD",
defValue: 100,
setup: func() {
os.Setenv("TEST_INT_BAD", "not-a-number")
},
cleanup: func() {
os.Unsetenv("TEST_INT_BAD")
},
want: 100,
},
}

for _, tt := range tests {
t.Run(tt.name, func(t *testing.T) {
tt.setup()
defer tt.cleanup()

got := getEnvInt(tt.key, tt.defValue)
if got != tt.want {
t.Errorf("getEnvInt() = %v, want %v", got, tt.want)
}
})
}
}

func TestGetEnvBool(t *testing.T) {
tests := []struct {
name     string
key      string
defValue bool
setup    func()
cleanup  func()
want     bool
}{
{
name:     "true value",
key:      "TEST_BOOL",
defValue: false,
setup: func() {
os.Setenv("TEST_BOOL", "true")
},
cleanup: func() {
os.Unsetenv("TEST_BOOL")
},
want: true,
},
{
name:     "false value",
key:      "TEST_BOOL_FALSE",
defValue: true,
setup: func() {
os.Setenv("TEST_BOOL_FALSE", "false")
},
cleanup: func() {
os.Unsetenv("TEST_BOOL_FALSE")
},
want: false,
},
{
name:     "yes value",
key:      "TEST_BOOL_YES",
defValue: false,
setup: func() {
os.Setenv("TEST_BOOL_YES", "yes")
},
cleanup: func() {
os.Unsetenv("TEST_BOOL_YES")
},
want: true,
},
}

for _, tt := range tests {
t.Run(tt.name, func(t *testing.T) {
tt.setup()
defer tt.cleanup()

got := getEnvBool(tt.key, tt.defValue)
if got != tt.want {
t.Errorf("getEnvBool() = %v, want %v", got, tt.want)
}
})
}
}
