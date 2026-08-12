package config

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

type Mode string

const (
	ModeLocal  Mode = "local"
	ModeRemote Mode = "remote"

	CurrentSchemaVersion      = 1
	maximumConfigurationBytes = 64 << 10
	maximumDatabaseDSNBytes   = 8 << 10
	maximumTokenTTLSeconds    = 30 * 24 * 60 * 60
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
}

type fileConfig struct {
	SchemaVersion                   *int    `json:"schema_version"`
	Mode                            *string `json:"mode"`
	Address                         *string `json:"address"`
	DatabaseDriver                  *string `json:"database_driver"`
	DatabaseDSN                     *string `json:"database_dsn"`
	LocalAccessToken                *string `json:"local_access_token"`
	ExitOnStdinClose                *bool   `json:"exit_on_stdin_close"`
	AuthTokenTTLSeconds             *int64  `json:"auth_token_ttl_seconds"`
	AllowRegistration               *bool   `json:"allow_registration"`
	AllowInsecureSensitiveTransport *bool   `json:"allow_insecure_sensitive_transport"`
	TrustProxyHeaders               *bool   `json:"trust_proxy_headers"`
}

var runtimeGOOS = runtime.GOOS

var currentConfigurationFields = map[string]struct{}{
	"schema_version":                     {},
	"mode":                               {},
	"address":                            {},
	"database_driver":                    {},
	"database_dsn":                       {},
	"local_access_token":                 {},
	"exit_on_stdin_close":                {},
	"auth_token_ttl_seconds":             {},
	"allow_registration":                 {},
	"allow_insecure_sensitive_transport": {},
	"trust_proxy_headers":                {},
}

// Load reads the complete runtime configuration from one permission-restricted
// JSON file. Product configuration deliberately has no environment-variable
// fallback, so a parent process cannot silently alter the data service.
func Load(path string) (Config, error) {
	if runtimeGOOS == "windows" {
		return Config{}, errors.New("the data API serve command requires Unix configuration-file permissions; Windows is not supported")
	}
	if strings.TrimSpace(path) == "" {
		return Config{}, errors.New("configuration path is required")
	}
	file, err := os.Open(path)
	if err != nil {
		return Config{}, fmt.Errorf("open configuration: %w", err)
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return Config{}, fmt.Errorf("inspect configuration: %w", err)
	}
	if !info.Mode().IsRegular() {
		return Config{}, errors.New("configuration must be a regular file")
	}
	if info.Mode().Perm() != 0o600 && info.Mode().Perm() != 0o400 {
		return Config{}, fmt.Errorf("configuration permissions %04o must be 0600 or 0400", info.Mode().Perm())
	}
	if info.Size() > maximumConfigurationBytes {
		return Config{}, fmt.Errorf("configuration exceeds %d bytes", maximumConfigurationBytes)
	}

	encoded, err := io.ReadAll(io.LimitReader(file, maximumConfigurationBytes+1))
	if err != nil {
		return Config{}, fmt.Errorf("read configuration: %w", err)
	}
	if len(encoded) > maximumConfigurationBytes {
		return Config{}, fmt.Errorf("configuration exceeds %d bytes", maximumConfigurationBytes)
	}
	if !utf8.Valid(encoded) {
		return Config{}, errors.New("configuration must be valid UTF-8")
	}
	if err := rejectDuplicateTopLevelKeys(encoded); err != nil {
		return Config{}, err
	}
	var raw fileConfig
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&raw); err != nil {
		return Config{}, fmt.Errorf("decode configuration: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return Config{}, errors.New("decode configuration: multiple JSON values are not allowed")
		}
		return Config{}, fmt.Errorf("decode configuration trailing data: %w", err)
	}
	return raw.validate()
}

func rejectDuplicateTopLevelKeys(encoded []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	opening, err := decoder.Token()
	if err != nil {
		return fmt.Errorf("decode configuration: %w", err)
	}
	if opening != json.Delim('{') {
		return errors.New("decode configuration: top-level value must be an object")
	}
	seen := make(map[string]struct{})
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return fmt.Errorf("decode configuration field name: %w", err)
		}
		key, ok := keyToken.(string)
		if !ok {
			return errors.New("decode configuration: field name must be a string")
		}
		if _, allowed := currentConfigurationFields[key]; !allowed {
			return fmt.Errorf("decode configuration: unknown field %q", key)
		}
		if _, duplicate := seen[key]; duplicate {
			return fmt.Errorf("decode configuration: duplicate field %q", key)
		}
		seen[key] = struct{}{}
		var value json.RawMessage
		if err := decoder.Decode(&value); err != nil {
			return fmt.Errorf("decode configuration field %q: %w", key, err)
		}
	}
	if _, err := decoder.Token(); err != nil {
		return fmt.Errorf("decode configuration: %w", err)
	}
	return nil
}

func (raw fileConfig) validate() (Config, error) {
	missing := make([]string, 0)
	require := func(name string, present bool) {
		if !present {
			missing = append(missing, name)
		}
	}
	require("schema_version", raw.SchemaVersion != nil)
	require("mode", raw.Mode != nil)
	require("address", raw.Address != nil)
	require("database_driver", raw.DatabaseDriver != nil)
	require("database_dsn", raw.DatabaseDSN != nil)
	require("local_access_token", raw.LocalAccessToken != nil)
	require("exit_on_stdin_close", raw.ExitOnStdinClose != nil)
	require("auth_token_ttl_seconds", raw.AuthTokenTTLSeconds != nil)
	require("allow_registration", raw.AllowRegistration != nil)
	require("allow_insecure_sensitive_transport", raw.AllowInsecureSensitiveTransport != nil)
	require("trust_proxy_headers", raw.TrustProxyHeaders != nil)
	if len(missing) != 0 {
		return Config{}, fmt.Errorf("configuration is missing required fields: %s", strings.Join(missing, ", "))
	}
	if *raw.SchemaVersion != CurrentSchemaVersion {
		return Config{}, fmt.Errorf(
			"unsupported configuration schema_version %d; expected %d",
			*raw.SchemaVersion,
			CurrentSchemaVersion,
		)
	}

	mode := Mode(*raw.Mode)
	if mode != ModeLocal && mode != ModeRemote {
		return Config{}, fmt.Errorf("mode must be %q or %q", ModeLocal, ModeRemote)
	}
	address := *raw.Address
	if address != strings.TrimSpace(address) || len(address) == 0 || len(address) > 255 {
		return Config{}, errors.New("address must contain 1-255 bytes without surrounding whitespace")
	}
	host, port, err := net.SplitHostPort(address)
	if err != nil || port == "" {
		return Config{}, fmt.Errorf("address must be a host:port pair: %w", err)
	}
	if host == "" {
		return Config{}, errors.New("address host must be explicit")
	}
	portNumber, err := strconv.Atoi(port)
	if err != nil || portNumber < 0 || portNumber > 65535 {
		return Config{}, errors.New("address port must be an integer between 0 and 65535")
	}
	if mode == ModeRemote && portNumber == 0 {
		return Config{}, errors.New("remote mode address port must not be zero")
	}
	if mode == ModeLocal {
		ip := net.ParseIP(host)
		if ip == nil || !ip.IsLoopback() {
			return Config{}, errors.New("local mode address must use a numeric loopback host")
		}
	}

	driver := *raw.DatabaseDriver
	if driver != "sqlite" && driver != "mysql" {
		return Config{}, errors.New("database_driver must be \"sqlite\" or \"mysql\"")
	}
	dsn := *raw.DatabaseDSN
	if dsn != strings.TrimSpace(dsn) || len(dsn) == 0 || len(dsn) > maximumDatabaseDSNBytes {
		return Config{}, fmt.Errorf("database_dsn must contain 1-%d bytes without surrounding whitespace", maximumDatabaseDSNBytes)
	}
	token := *raw.LocalAccessToken
	if mode == ModeLocal {
		decoded, err := base64.RawURLEncoding.DecodeString(token)
		if err != nil || len(token) != 43 || len(decoded) != 32 || base64.RawURLEncoding.EncodeToString(decoded) != token {
			return Config{}, errors.New("local mode local_access_token must be 32 random bytes encoded as canonical unpadded base64url")
		}
	}
	if mode == ModeRemote && token != "" {
		return Config{}, errors.New("remote mode local_access_token must be empty")
	}
	if *raw.AuthTokenTTLSeconds < 1 || *raw.AuthTokenTTLSeconds > maximumTokenTTLSeconds {
		return Config{}, fmt.Errorf("auth_token_ttl_seconds must be between 1 and %d", maximumTokenTTLSeconds)
	}
	if mode == ModeLocal && *raw.AllowRegistration {
		return Config{}, errors.New("local mode allow_registration must be false")
	}
	if mode == ModeLocal && *raw.TrustProxyHeaders {
		return Config{}, errors.New("local mode trust_proxy_headers must be false")
	}
	if mode == ModeLocal && *raw.AllowInsecureSensitiveTransport {
		return Config{}, errors.New("local mode allow_insecure_sensitive_transport must be false")
	}

	return Config{
		Mode:                            mode,
		Address:                         address,
		DatabaseDriver:                  driver,
		DatabaseDSN:                     dsn,
		LocalAccessToken:                token,
		ExitOnStdinClose:                *raw.ExitOnStdinClose,
		TokenTTL:                        time.Duration(*raw.AuthTokenTTLSeconds) * time.Second,
		AllowRegistration:               *raw.AllowRegistration,
		AllowInsecureSensitiveTransport: *raw.AllowInsecureSensitiveTransport,
		TrustProxyHeaders:               *raw.TrustProxyHeaders,
	}, nil
}
