package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/httpapi"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/secure"
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

func TestLocalSetupRejectsRotationAfterTheKeyIsCreated(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeLocal)
	first := request(t, handler, http.MethodPost, "/v1/auth/setup", map[string]any{
		"encryption_key": "immutable-local-key-material",
	}, nil)
	if first.Code != http.StatusCreated {
		t.Fatalf("initial setup status = %d", first.Code)
	}

	rotation := request(t, handler, http.MethodPost, "/v1/auth/setup", map[string]any{
		"encryption_key": "replacement-local-key-material",
	}, nil)
	if rotation.Code != http.StatusUnauthorized ||
		!strings.Contains(rotation.Body.String(), `"code":"invalid_encryption_key"`) {
		t.Fatalf("rotation attempt status = %d, body = %s", rotation.Code, rotation.Body.String())
	}
}

func TestEncryptionKeyEndpointsRejectOversizedSecrets(t *testing.T) {
	oversized := strings.Repeat("x", secure.MaximumUserKeyBytes+1)

	_, _, localHandler := testAPI(t, config.ModeLocal)
	setup := request(t, localHandler, http.MethodPost, "/v1/auth/setup", map[string]any{
		"encryption_key": oversized,
	}, nil)
	assertTypedError(t, setup, http.StatusBadRequest, "encryption_key_too_long")

	_, _, remoteHandler := testAPI(t, config.ModeRemote)
	registration := request(t, remoteHandler, http.MethodPost, "/v1/auth/register", map[string]any{
		"username":       "bounded-key-user",
		"password":       "bounded-password-value",
		"encryption_key": oversized,
	}, nil)
	assertTypedError(t, registration, http.StatusBadRequest, "encryption_key_too_long")

	session := register(
		t,
		remoteHandler,
		"verify-key-limit-user",
		"verify-key-password",
		"bounded-verification-key",
	)
	verification := request(t, remoteHandler, http.MethodPost, "/v1/auth/verify-key", nil, map[string]string{
		"Authorization":          "Bearer " + session.Token,
		"X-Ianvs-Encryption-Key": oversized,
	})
	assertTypedError(t, verification, http.StatusBadRequest, "encryption_key_too_long")
}

func TestPutExpectedRevisionZeroHasCreateIfAbsentContract(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeLocal)
	create := func(name string, expectedRevision int64) *httptest.ResponseRecorder {
		return request(t, handler, http.MethodPut, "/v1/resources/profile/default", map[string]any{
			"data":              map[string]any{"name": name},
			"expected_revision": expectedRevision,
		}, nil)
	}

	response := create("First", 0)
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `"revision":1`) {
		t.Fatalf("first create status = %d, body = %s", response.Code, response.Body.String())
	}
	response = create("Lost update", 0)
	if response.Code != http.StatusConflict || !strings.Contains(response.Body.String(), `"code":"revision_conflict"`) {
		t.Fatalf("duplicate create status = %d, body = %s", response.Code, response.Body.String())
	}
	response = create("Invalid", -1)
	if response.Code != http.StatusBadRequest || !strings.Contains(response.Body.String(), `"code":"invalid_request"`) {
		t.Fatalf("negative revision status = %d, body = %s", response.Code, response.Body.String())
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
	revokedLogoutResponse := request(t, handler, http.MethodPost, "/v1/auth/logout", nil, map[string]string{
		"Authorization": "Bearer " + login.Token,
	})
	if revokedLogoutResponse.Code != http.StatusUnauthorized ||
		!strings.Contains(revokedLogoutResponse.Body.String(), `"code":"unauthorized"`) {
		t.Fatalf(
			"revoked logout status = %d, body = %s",
			revokedLogoutResponse.Code,
			revokedLogoutResponse.Body.String(),
		)
	}
	meResponse := request(t, handler, http.MethodGet, "/v1/me", nil, map[string]string{
		"Authorization": "Bearer " + login.Token,
	})
	if meResponse.Code != http.StatusUnauthorized {
		t.Fatalf("revoked token status = %d, body = %s", meResponse.Code, meResponse.Body.String())
	}
}

func TestRemoteLoginRateLimitUsesSocketPeerAndIgnoresForwardedFor(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeRemote)
	for attempt := 0; attempt < 10; attempt++ {
		response := requestFromPeer(
			t,
			handler,
			http.MethodPost,
			"/v1/auth/login",
			map[string]any{"username": "missing-user", "password": "redacted-password"},
			"192.0.2.40:41000",
			map[string]string{"X-Forwarded-For": "198.51.100." + strconv.Itoa(attempt+1)},
		)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("login attempt %d status = %d", attempt+1, response.Code)
		}
	}
	limited := requestFromPeer(
		t,
		handler,
		http.MethodPost,
		"/v1/auth/login",
		map[string]any{"username": "missing-user", "password": "redacted-password"},
		"192.0.2.40:42000",
		map[string]string{"X-Forwarded-For": "203.0.113.200"},
	)
	assertRateLimited(t, limited)

	otherPeer := requestFromPeer(
		t,
		handler,
		http.MethodPost,
		"/v1/auth/login",
		map[string]any{"username": "missing-user", "password": "redacted-password"},
		"192.0.2.41:41000",
		nil,
	)
	if otherPeer.Code != http.StatusUnauthorized {
		t.Fatalf("different peer login status = %d", otherPeer.Code)
	}
}

func TestRemoteRegistrationRateLimitRunsBeforeRequestDecoding(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeRemote)
	for attempt := 0; attempt < 10; attempt++ {
		response := requestFromPeer(
			t,
			handler,
			http.MethodPost,
			"/v1/auth/register",
			nil,
			"192.0.2.50:41000",
			nil,
		)
		if response.Code != http.StatusUnsupportedMediaType {
			t.Fatalf("registration attempt %d status = %d", attempt+1, response.Code)
		}
	}
	limited := requestFromPeer(
		t,
		handler,
		http.MethodPost,
		"/v1/auth/register",
		nil,
		"192.0.2.50:42000",
		nil,
	)
	assertRateLimited(t, limited)
}

func TestVerifyKeyIsBoundedAndIndependentOfResourceCount(t *testing.T) {
	_, db, handler := testAPI(t, config.ModeRemote)
	key := "verify-key-without-resources"
	session := register(t, handler, "key-verifier", "verify-password-long", key)

	var resourceCount int64
	if err := db.Model(&model.Resource{}).Count(&resourceCount).Error; err != nil {
		t.Fatalf("count resources: %v", err)
	}
	if resourceCount != 0 {
		t.Fatalf("resource count before verification = %d, want 0", resourceCount)
	}

	verify := func(providedKey string) *httptest.ResponseRecorder {
		headers := map[string]string{"Authorization": "Bearer " + session.Token}
		if providedKey != "" {
			headers["X-Ianvs-Encryption-Key"] = providedKey
		}
		return request(t, handler, http.MethodPost, "/v1/auth/verify-key", nil, headers)
	}
	response := verify(key)
	if response.Code != http.StatusOK ||
		!strings.Contains(response.Body.String(), `"verified":true`) ||
		!strings.Contains(response.Body.String(), `"basis":"account_key_verifier"`) ||
		!strings.Contains(response.Body.String(), `"key_contract_version":1`) ||
		!strings.Contains(response.Body.String(), `"key_rotation_supported":false`) {
		t.Fatalf("verify key status = %d, body = %s", response.Code, response.Body.String())
	}
	response = verify("different-verification-key")
	if response.Code != http.StatusUnauthorized || !strings.Contains(response.Body.String(), `"code":"invalid_encryption_key"`) {
		t.Fatalf("wrong key status = %d, body = %s", response.Code, response.Body.String())
	}
	response = verify("")
	if response.Code != http.StatusPreconditionRequired || !strings.Contains(response.Body.String(), `"code":"encryption_key_required"`) {
		t.Fatalf("missing key status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestResourceListUsesBoundedStableCursorPages(t *testing.T) {
	_, _, handler := testAPI(t, config.ModeLocal)
	for _, id := range []string{"first", "second", "third"} {
		response := request(t, handler, http.MethodPut, "/v1/resources/profile/"+id, map[string]any{
			"data": map[string]any{"id": id},
		}, nil)
		if response.Code != http.StatusOK {
			t.Fatalf("put %s status = %d, body = %s", id, response.Code, response.Body.String())
		}
	}

	first := request(t, handler, http.MethodGet, "/v1/resources?limit=2", nil, nil)
	if first.Code != http.StatusOK || first.Body.Len() > store.MaximumJSONResponseBytes {
		t.Fatalf("first page status/bytes = %d/%d, body = %s", first.Code, first.Body.Len(), first.Body.String())
	}
	var firstPage store.ResourcePage
	if err := json.Unmarshal(first.Body.Bytes(), &firstPage); err != nil {
		t.Fatalf("decode first page: %v", err)
	}
	if len(firstPage.Resources) != 2 || firstPage.NextCursor == "" {
		t.Fatalf("first page = %#v", firstPage)
	}

	mismatched := request(
		t,
		handler,
		http.MethodGet,
		"/v1/resources?kind=profile&limit=2&cursor="+firstPage.NextCursor,
		nil,
		nil,
	)
	assertTypedError(t, mismatched, http.StatusBadRequest, "invalid_cursor")

	second := request(
		t,
		handler,
		http.MethodGet,
		"/v1/resources?limit=2&cursor="+firstPage.NextCursor,
		nil,
		nil,
	)
	if second.Code != http.StatusOK {
		t.Fatalf("second page status = %d, body = %s", second.Code, second.Body.String())
	}
	var secondPage store.ResourcePage
	if err := json.Unmarshal(second.Body.Bytes(), &secondPage); err != nil {
		t.Fatalf("decode second page: %v", err)
	}
	if len(secondPage.Resources) != 1 || secondPage.NextCursor != "" {
		t.Fatalf("second page = %#v", secondPage)
	}
	if secondPage.Resources[0].ID == firstPage.Resources[0].ID ||
		secondPage.Resources[0].ID == firstPage.Resources[1].ID {
		t.Fatalf("resource repeated across pages: %#v / %#v", firstPage, secondPage)
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
	cfg, cleanup, err := contracttest.NewDatabaseConfiguration(
		context.Background(),
		mode,
		filepath.Join(t.TempDir(), "api.db"),
	)
	if err != nil {
		t.Fatalf("create contract database configuration: %v", err)
	}
	t.Cleanup(func() {
		if err := cleanup(); err != nil {
			t.Errorf("clean up contract database: %v", err)
		}
	})
	cfg.AllowRegistration = true
	cfg.AllowInsecureSensitiveTransport = mode == config.ModeRemote
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
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("database pool error = %v", err)
	}
	t.Cleanup(func() {
		if err := sqlDB.Close(); err != nil {
			t.Errorf("close contract database: %v", err)
		}
	})
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
	return requestFromPeer(t, handler, method, target, body, "127.0.0.1:54321", headers)
}

func requestFromPeer(
	t *testing.T,
	handler http.Handler,
	method, target string,
	body any,
	remoteAddress string,
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
	req.RemoteAddr = remoteAddress
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

func assertRateLimited(t *testing.T, response *httptest.ResponseRecorder) {
	t.Helper()
	assertTypedError(t, response, http.StatusTooManyRequests, "authentication_rate_limited")
	if response.Header().Get("Retry-After") == "" {
		t.Fatal("rate-limited response omitted Retry-After")
	}
}

func assertTypedError(
	t *testing.T,
	response *httptest.ResponseRecorder,
	status int,
	code string,
) {
	t.Helper()
	if response.Code != status || !strings.Contains(response.Body.String(), `"code":"`+code+`"`) {
		t.Fatalf("typed error status = %d, want %d/%s", response.Code, status, code)
	}
}
