package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/httpapi"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/store"
)

func TestLocalAPISetupAndEncryptedResourceRoundTrip(t *testing.T) {
	cfg, db, handler := testAPI(t, config.ModeLocal)
	_ = cfg
	key := "locally-created-encryption-key-material"

	response := request(t, handler, http.MethodPost, "/v1/auth/setup", map[string]any{
		"encryption_key": key,
	}, nil)
	if response.Code != http.StatusCreated {
		t.Fatalf("setup status = %d, body = %s", response.Code, response.Body.String())
	}

	response = request(t, handler, http.MethodPut, "/v1/resources/profile/work", map[string]any{
		"data":      map[string]any{"name": "Work", "host": "example.com"},
		"sensitive": map[string]any{"password": "api-secret"},
	}, map[string]string{"X-Ianvs-Encryption-Key": key})
	if response.Code != http.StatusOK {
		t.Fatalf("put status = %d, body = %s", response.Code, response.Body.String())
	}

	var persisted model.Resource
	if err := db.Where("kind = ? AND external_id = ?", "profile", "work").First(&persisted).Error; err != nil {
		t.Fatalf("load resource: %v", err)
	}
	if strings.Contains(persisted.SensitiveCiphertext, "api-secret") || strings.Contains(persisted.PlainJSON, "api-secret") {
		t.Fatal("API persisted sensitive data in plaintext")
	}

	response = request(t, handler, http.MethodGet, "/v1/resources/profile/work", nil, nil)
	if response.Code != http.StatusOK || strings.Contains(response.Body.String(), "api-secret") {
		t.Fatalf("plain get status = %d, body = %s", response.Code, response.Body.String())
	}
	response = request(t, handler, http.MethodGet, "/v1/resources/profile/work?include_sensitive=true", nil, nil)
	if response.Code != http.StatusPreconditionRequired {
		t.Fatalf("keyless sensitive get status = %d, body = %s", response.Code, response.Body.String())
	}
	response = request(t, handler, http.MethodGet, "/v1/resources/profile/work?include_sensitive=true", nil, map[string]string{
		"X-Ianvs-Encryption-Key": key,
	})
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), "api-secret") {
		t.Fatalf("sensitive get status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestLocalSetupRejectsBrowserSimpleContentType(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeLocal)
	req := httptest.NewRequest(
		http.MethodPost,
		"/v1/auth/setup",
		strings.NewReader(`{"encryption_key":"attacker-controlled-key"}`),
	)
	req.RemoteAddr = "127.0.0.1:54321"
	req.Header.Set("Content-Type", "text/plain")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, req)
	if response.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("setup status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestLocalAccessTokenProtectsHealthAndAPI(t *testing.T) {
	cfg, _, _ := testAPI(t, config.ModeLocal)
	cfg.LocalAccessToken = "parent-owned-token"
	handler := testAPIHandler(t, cfg)

	unauthorized := request(t, handler, http.MethodGet, "/healthz", nil, nil)
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized health status = %d, body = %s", unauthorized.Code, unauthorized.Body.String())
	}
	authorized := request(t, handler, http.MethodGet, "/healthz", nil, map[string]string{
		"Authorization": "Bearer parent-owned-token",
	})
	if authorized.Code != http.StatusOK {
		t.Fatalf("authorized health status = %d, body = %s", authorized.Code, authorized.Body.String())
	}
}

func TestRemoteAPIIsolatesUsersWithBearerAuthentication(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeRemote)
	alice := register(t, handler, "alice", "alice-password-long", "alice-encryption-key-material")
	bob := register(t, handler, "bob", "bob-password-is-long", "bob-encryption-key-material")

	putForUser(t, handler, alice.Token, "alice-encryption-key-material", "Alice profile", "alice-secret")
	putForUser(t, handler, bob.Token, "bob-encryption-key-material", "Bob profile", "bob-secret")

	aliceResponse := request(t, handler, http.MethodGet, "/v1/resources/profile/shared?include_sensitive=true", nil, map[string]string{
		"Authorization":          "Bearer " + alice.Token,
		"X-Ianvs-Encryption-Key": "alice-encryption-key-material",
	})
	if aliceResponse.Code != http.StatusOK || !strings.Contains(aliceResponse.Body.String(), "Alice profile") || !strings.Contains(aliceResponse.Body.String(), "alice-secret") || strings.Contains(aliceResponse.Body.String(), "bob-secret") {
		t.Fatalf("alice get status = %d, body = %s", aliceResponse.Code, aliceResponse.Body.String())
	}
	bobResponse := request(t, handler, http.MethodGet, "/v1/resources/profile/shared?include_sensitive=true", nil, map[string]string{
		"Authorization":          "Bearer " + bob.Token,
		"X-Ianvs-Encryption-Key": "bob-encryption-key-material",
	})
	if bobResponse.Code != http.StatusOK || !strings.Contains(bobResponse.Body.String(), "Bob profile") || !strings.Contains(bobResponse.Body.String(), "bob-secret") || strings.Contains(bobResponse.Body.String(), "alice-secret") {
		t.Fatalf("bob get status = %d, body = %s", bobResponse.Code, bobResponse.Body.String())
	}

	unauthorized := request(t, handler, http.MethodGet, "/v1/resources", nil, nil)
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized list status = %d, body = %s", unauthorized.Code, unauthorized.Body.String())
	}
}

func TestRemoteLoginAndLogoutLifecycle(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeRemote)
	register(t, handler, "login-user", "login-password-long", "login-encryption-key-material")

	wrongPassword := request(t, handler, http.MethodPost, "/v1/auth/login", map[string]any{
		"username": "login-user",
		"password": "wrong-password-long",
	}, nil)
	if wrongPassword.Code != http.StatusUnauthorized {
		t.Fatalf("wrong password status = %d, body = %s", wrongPassword.Code, wrongPassword.Body.String())
	}
	loginResponse := request(t, handler, http.MethodPost, "/v1/auth/login", map[string]any{
		"username": "login-user",
		"password": "login-password-long",
	}, nil)
	if loginResponse.Code != http.StatusOK {
		t.Fatalf("login status = %d, body = %s", loginResponse.Code, loginResponse.Body.String())
	}
	var login registrationSession
	if err := json.Unmarshal(loginResponse.Body.Bytes(), &login); err != nil {
		t.Fatalf("decode login: %v", err)
	}
	logoutResponse := request(t, handler, http.MethodPost, "/v1/auth/logout", nil, map[string]string{
		"Authorization": "Bearer " + login.Token,
	})
	if logoutResponse.Code != http.StatusNoContent {
		t.Fatalf("logout status = %d, body = %s", logoutResponse.Code, logoutResponse.Body.String())
	}
	meResponse := request(t, handler, http.MethodGet, "/v1/me", nil, map[string]string{
		"Authorization": "Bearer " + login.Token,
	})
	if meResponse.Code != http.StatusUnauthorized {
		t.Fatalf("revoked token status = %d, body = %s", meResponse.Code, meResponse.Body.String())
	}
}

func TestExportResponseCanBePostedDirectlyToRemoteMerge(t *testing.T) {
	_, _, localHandler := testAPI(t, config.ModeLocal)
	localKey := "local-export-encryption-key"
	response := request(t, localHandler, http.MethodPost, "/v1/auth/setup", map[string]any{
		"encryption_key": localKey,
	}, nil)
	if response.Code != http.StatusCreated {
		t.Fatalf("local setup status = %d, body = %s", response.Code, response.Body.String())
	}
	response = request(t, localHandler, http.MethodPut, "/v1/resources/profile/migrated", map[string]any{
		"data":      map[string]any{"name": "Migrated"},
		"sensitive": map[string]any{"password": "migration-secret"},
	}, map[string]string{"X-Ianvs-Encryption-Key": localKey})
	if response.Code != http.StatusOK {
		t.Fatalf("local put status = %d, body = %s", response.Code, response.Body.String())
	}
	response = request(t, localHandler, http.MethodGet, "/v1/migrations/export?include_sensitive=true", nil, map[string]string{
		"X-Ianvs-Encryption-Key": localKey,
	})
	if response.Code != http.StatusOK {
		t.Fatalf("export status = %d, body = %s", response.Code, response.Body.String())
	}
	var bundle any
	if err := json.Unmarshal(response.Body.Bytes(), &bundle); err != nil {
		t.Fatalf("decode export bundle: %v", err)
	}

	_, _, remoteHandler := testAPI(t, config.ModeRemote)
	remoteKey := "different-remote-encryption-key"
	remote := register(t, remoteHandler, "migrator", "migration-password-long", remoteKey)
	response = request(t, remoteHandler, http.MethodPost, "/v1/migrations/merge", bundle, map[string]string{
		"Authorization":          "Bearer " + remote.Token,
		"X-Ianvs-Encryption-Key": remoteKey,
	})
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `"created":1`) {
		t.Fatalf("merge status = %d, body = %s", response.Code, response.Body.String())
	}
	response = request(t, remoteHandler, http.MethodGet, "/v1/resources/profile/migrated?include_sensitive=true", nil, map[string]string{
		"Authorization":          "Bearer " + remote.Token,
		"X-Ianvs-Encryption-Key": remoteKey,
	})
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), "migration-secret") {
		t.Fatalf("merged get status = %d, body = %s", response.Code, response.Body.String())
	}
}

type registrationSession struct {
	Token string `json:"token"`
}

func register(t *testing.T, handler http.Handler, username, password, encryptionKey string) registrationSession {
	t.Helper()
	response := request(t, handler, http.MethodPost, "/v1/auth/register", map[string]any{
		"username":       username,
		"password":       password,
		"encryption_key": encryptionKey,
	}, nil)
	if response.Code != http.StatusCreated {
		t.Fatalf("register %s status = %d, body = %s", username, response.Code, response.Body.String())
	}
	var session registrationSession
	if err := json.Unmarshal(response.Body.Bytes(), &session); err != nil {
		t.Fatalf("decode registration: %v", err)
	}
	if session.Token == "" {
		t.Fatal("registration did not return a token")
	}
	return session
}

func putForUser(t *testing.T, handler http.Handler, token, key, name, secret string) {
	t.Helper()
	response := request(t, handler, http.MethodPut, "/v1/resources/profile/shared", map[string]any{
		"data":      map[string]any{"name": name},
		"sensitive": map[string]any{"password": secret},
	}, map[string]string{
		"Authorization":          "Bearer " + token,
		"X-Ianvs-Encryption-Key": key,
	})
	if response.Code != http.StatusOK {
		t.Fatalf("put %s status = %d, body = %s", name, response.Code, response.Body.String())
	}
}

func testAPI(t *testing.T, mode config.Mode) (config.Config, *gorm.DB, http.Handler) {
	t.Helper()
	cfg := config.Config{
		Mode:                            mode,
		DatabaseDriver:                  "sqlite",
		DatabaseDSN:                     filepath.Join(t.TempDir(), "api.db"),
		TokenTTL:                        time.Hour,
		AllowRegistration:               true,
		AllowInsecureSensitiveTransport: mode == config.ModeRemote,
	}
	db, handler := testAPIHandlerAndDB(t, cfg)
	return cfg, db, handler
}

func testAPIHandler(t *testing.T, cfg config.Config) http.Handler {
	t.Helper()
	_, handler := testAPIHandlerAndDB(t, cfg)
	return handler
}

func testAPIHandlerAndDB(t *testing.T, cfg config.Config) (*gorm.DB, http.Handler) {
	t.Helper()
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("database.Open() error = %v", err)
	}
	resourceStore, err := store.New(context.Background(), db)
	if err != nil {
		t.Fatalf("store.New() error = %v", err)
	}
	authService := auth.New(db, cfg.TokenTTL)
	if cfg.Mode == config.ModeLocal {
		if _, err := authService.EnsureLocalUser(context.Background()); err != nil {
			t.Fatalf("EnsureLocalUser() error = %v", err)
		}
	}
	return db, httpapi.New(cfg, authService, resourceStore).Handler()
}

func request(
	t *testing.T,
	handler http.Handler,
	method, target string,
	body any,
	headers map[string]string,
) *httptest.ResponseRecorder {
	t.Helper()
	var encoded []byte
	if body != nil {
		var err error
		encoded, err = json.Marshal(body)
		if err != nil {
			t.Fatalf("encode request: %v", err)
		}
	}
	req := httptest.NewRequest(method, target, bytes.NewReader(encoded))
	req.RemoteAddr = "127.0.0.1:54321"
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, req)
	return response
}
