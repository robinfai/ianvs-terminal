package config

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

const validLocalConfiguration = `{
  "schema_version": 1,
  "mode": "local",
  "address": "127.0.0.1:0",
  "database_driver": "sqlite",
  "database_dsn": "/tmp/ianvs.db",
  "local_access_token": "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY",
  "exit_on_stdin_close": true,
  "auth_token_ttl_seconds": 3600,
  "allow_registration": false,
  "allow_insecure_sensitive_transport": false,
  "trust_proxy_headers": false
}`

func TestLoadReadsStrictCurrentConfiguration(t *testing.T) {
	path := writeConfiguration(t, validLocalConfiguration, 0o600)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Mode != ModeLocal || cfg.Address != "127.0.0.1:0" || cfg.DatabaseDriver != "sqlite" {
		t.Fatalf("Load() identity fields = %#v", cfg)
	}
	if cfg.TokenTTL != time.Hour || !cfg.ExitOnStdinClose {
		t.Fatalf("Load() lifecycle fields = %#v", cfg)
	}
}

func TestLoadRejectsMissingUnknownAndTrailingFields(t *testing.T) {
	tests := map[string]string{
		"missing":   strings.Replace(validLocalConfiguration, `  "schema_version": 1,`+"\n", "", 1),
		"unknown":   strings.Replace(validLocalConfiguration, `"schema_version": 1`, `"schema_version": 1, "old_mode": true`, 1),
		"duplicate": strings.Replace(validLocalConfiguration, `"schema_version": 1`, `"schema_version": 1, "schema_version": 1`, 1),
		"trailing":  validLocalConfiguration + `{}`,
	}
	for name, encoded := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := Load(writeConfiguration(t, encoded, 0o600))
			if err == nil {
				t.Fatal("Load() error = nil, want strict schema rejection")
			}
		})
	}
}

func TestLoadRejectsEveryCaseAliasedFieldNameAndAliasConflict(t *testing.T) {
	for field := range currentConfigurationFields {
		alias := strings.ToUpper(field[:1]) + field[1:]
		t.Run(field, func(t *testing.T) {
			encoded := strings.Replace(validLocalConfiguration, `"`+field+`"`, `"`+alias+`"`, 1)
			_, err := Load(writeConfiguration(t, encoded, 0o600))
			if err == nil || !strings.Contains(err.Error(), "unknown field") {
				t.Fatalf("Load() error = %v, want exact field-name rejection", err)
			}
		})
	}
	conflict := strings.Replace(
		validLocalConfiguration,
		`"mode": "local"`,
		`"mode": "local", "Mode": "remote"`,
		1,
	)
	_, err := Load(writeConfiguration(t, conflict, 0o600))
	if err == nil || !strings.Contains(err.Error(), "unknown field") {
		t.Fatalf("Load() alias conflict error = %v, want exact field-name rejection", err)
	}
}

func TestLoadRejectsInvalidUTF8InSecrets(t *testing.T) {
	for _, field := range []string{"database_dsn", "local_access_token"} {
		t.Run(field, func(t *testing.T) {
			encoded := []byte(validLocalConfiguration)
			marker := []byte(`"` + field + `": "`)
			index := strings.Index(string(encoded), string(marker))
			if index < 0 {
				t.Fatalf("test fixture omitted %s", field)
			}
			encoded[index+len(marker)] = 0xff
			path := filepath.Join(t.TempDir(), "configuration.json")
			if err := os.WriteFile(path, encoded, 0o600); err != nil {
				t.Fatalf("write configuration: %v", err)
			}
			_, err := Load(path)
			if err == nil || !strings.Contains(err.Error(), "valid UTF-8") {
				t.Fatalf("Load() error = %v, want UTF-8 rejection", err)
			}
		})
	}
}

func TestLoadRejectsNonCurrentSchemaAndUnsafeLocalBoundary(t *testing.T) {
	tests := map[string]string{
		"schema": strings.Replace(validLocalConfiguration, `"schema_version": 1`, `"schema_version": 2`, 1),
		"bind":   strings.Replace(validLocalConfiguration, `"127.0.0.1:0"`, `"0.0.0.0:47832"`, 1),
		"token": strings.Replace(
			validLocalConfiguration,
			`"MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY"`,
			`"short"`,
			1,
		),
	}
	for name, encoded := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := Load(writeConfiguration(t, encoded, 0o600))
			if err == nil {
				t.Fatal("Load() error = nil, want current-contract rejection")
			}
		})
	}
}

func TestLoadRejectsConfigurationExposedToOtherUsers(t *testing.T) {
	_, err := Load(writeConfiguration(t, validLocalConfiguration, 0o644))
	if err == nil || !strings.Contains(err.Error(), "permissions") {
		t.Fatalf("Load() error = %v, want permission rejection", err)
	}
}

func TestLoadFailsClosedOnWindows(t *testing.T) {
	original := runtimeGOOS
	runtimeGOOS = "windows"
	t.Cleanup(func() { runtimeGOOS = original })
	_, err := Load(writeConfiguration(t, validLocalConfiguration, 0o600))
	if err == nil || !strings.Contains(err.Error(), "Windows is not supported") {
		t.Fatalf("Load() error = %v, want fail-closed Windows rejection", err)
	}
}

func TestReadmeLocalConfigurationExampleMatchesCurrentContract(t *testing.T) {
	readme, err := os.ReadFile("../../README.md")
	if err != nil {
		t.Fatalf("read backend README: %v", err)
	}
	match := regexp.MustCompile("(?s)```json\\n(\\{.*?\\n\\})\\n```").FindSubmatch(readme)
	if len(match) != 2 {
		t.Fatal("README omitted local JSON configuration example")
	}
	if _, err := Load(writeConfiguration(t, string(match[1]), 0o600)); err != nil {
		t.Fatalf("README local configuration does not satisfy current contract: %v", err)
	}
}

func writeConfiguration(t *testing.T, encoded string, permissions os.FileMode) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "configuration.json")
	if err := os.WriteFile(path, []byte(encoded), permissions); err != nil {
		t.Fatalf("write configuration: %v", err)
	}
	return path
}
