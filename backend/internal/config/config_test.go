package config

import "testing"

func TestFromEnvReadsSidecarLifecycleConfiguration(t *testing.T) {
	t.Setenv("IANVS_API_MODE", "local")
	t.Setenv("IANVS_DB_DSN", t.TempDir()+"/ianvs.db")
	t.Setenv("IANVS_LOCAL_ACCESS_TOKEN", "  parent-owned-token  ")
	t.Setenv("IANVS_EXIT_ON_STDIN_CLOSE", "true")

	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.LocalAccessToken != "parent-owned-token" {
		t.Fatalf("LocalAccessToken = %q", cfg.LocalAccessToken)
	}
	if !cfg.ExitOnStdinClose {
		t.Fatal("ExitOnStdinClose = false, want true")
	}
}

func TestFromEnvRejectsInvalidExitOnStdinClose(t *testing.T) {
	t.Setenv("IANVS_EXIT_ON_STDIN_CLOSE", "sometimes")

	_, err := FromEnv()
	if err == nil {
		t.Fatal("FromEnv() error = nil, want invalid boolean error")
	}
}

func TestFromEnvKeepsRemoteRegistrationClosedByDefault(t *testing.T) {
	t.Setenv("IANVS_API_MODE", "remote")
	t.Setenv("IANVS_DB_DSN", t.TempDir()+"/ianvs.db")
	t.Setenv("IANVS_ALLOW_REGISTRATION", "")

	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.AllowRegistration {
		t.Fatal("AllowRegistration = true, want fail-closed default")
	}
}
