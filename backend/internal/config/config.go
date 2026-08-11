package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Mode string

const (
	ModeLocal  Mode = "local"
	ModeRemote Mode = "remote"
)

type Config struct {
	Mode                            Mode
	Address                         string
	DatabaseDriver                  string
	DatabaseDSN                     string
	LocalAccessToken                string
	ExitOnStdinClose                bool
	TokenTTL                        time.Duration
	AllowRegistration               bool
	AllowInsecureSensitiveTransport bool
	TrustProxyHeaders               bool
	LegacyDirectory                 string
	LegacyProfileKey                string
	EncryptionKey                   string
}

func FromEnv() (Config, error) {
	mode := Mode(strings.ToLower(envOr("IANVS_API_MODE", string(ModeLocal))))
	if mode != ModeLocal && mode != ModeRemote {
		return Config{}, fmt.Errorf("IANVS_API_MODE must be %q or %q", ModeLocal, ModeRemote)
	}

	driver := strings.ToLower(envOr("IANVS_DB_DRIVER", "sqlite"))
	if driver != "sqlite" && driver != "mysql" {
		return Config{}, errors.New("IANVS_DB_DRIVER must be \"sqlite\" or \"mysql\"")
	}
	dsn := strings.TrimSpace(os.Getenv("IANVS_DB_DSN"))
	if dsn == "" {
		if driver == "mysql" {
			return Config{}, errors.New("IANVS_DB_DSN is required when IANVS_DB_DRIVER=mysql")
		}
		dsn = "ianvs.db"
	}

	tokenTTL, err := time.ParseDuration(envOr("IANVS_AUTH_TOKEN_TTL", "24h"))
	if err != nil || tokenTTL <= 0 {
		return Config{}, errors.New("IANVS_AUTH_TOKEN_TTL must be a positive duration")
	}
	allowRegistration, err := envBool("IANVS_ALLOW_REGISTRATION", true)
	if err != nil {
		return Config{}, err
	}
	allowInsecure, err := envBool("IANVS_ALLOW_INSECURE_SENSITIVE_TRANSPORT", false)
	if err != nil {
		return Config{}, err
	}
	trustProxyHeaders, err := envBool("IANVS_TRUST_PROXY_HEADERS", false)
	if err != nil {
		return Config{}, err
	}
	exitOnStdinClose, err := envBool("IANVS_EXIT_ON_STDIN_CLOSE", false)
	if err != nil {
		return Config{}, err
	}

	address := strings.TrimSpace(os.Getenv("IANVS_API_ADDR"))
	if address == "" {
		if mode == ModeRemote {
			address = "0.0.0.0:47832"
		} else {
			address = "127.0.0.1:47832"
		}
	}

	return Config{
		Mode:                            mode,
		Address:                         address,
		DatabaseDriver:                  driver,
		DatabaseDSN:                     dsn,
		LocalAccessToken:                strings.TrimSpace(os.Getenv("IANVS_LOCAL_ACCESS_TOKEN")),
		ExitOnStdinClose:                exitOnStdinClose,
		TokenTTL:                        tokenTTL,
		AllowRegistration:               allowRegistration,
		AllowInsecureSensitiveTransport: allowInsecure,
		TrustProxyHeaders:               trustProxyHeaders,
		LegacyDirectory:                 strings.TrimSpace(os.Getenv("IANVS_LEGACY_DATA_DIR")),
		LegacyProfileKey:                strings.TrimSpace(os.Getenv("IANVS_LEGACY_PROFILE_KEY")),
		EncryptionKey:                   os.Getenv("IANVS_ENCRYPTION_KEY"),
	}, nil
}

func envOr(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func envBool(key string, fallback bool) (bool, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("%s must be a boolean: %w", key, err)
	}
	return parsed, nil
}
