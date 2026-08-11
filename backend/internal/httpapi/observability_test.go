package httpapi

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestWithRecoveryLogsPanicWithoutRequestSecrets(t *testing.T) {
	t.Parallel()

	var logs bytes.Buffer
	api := &API{logger: slog.New(slog.NewJSONHandler(&logs, nil))}
	handler := api.withRecovery(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		r.Pattern = "GET /v1/resources/{kind}/{id}"
		panic("panic-secret-must-not-be-logged")
	}))
	request := httptest.NewRequest(
		http.MethodGet,
		"/v1/resources/profile/private?token=query-secret",
		nil,
	)
	request.Header.Set(requestIDHeader, "request-123")
	request.Header.Set("Authorization", "Bearer authorization-secret")
	request.Header.Set(encryptionKeyHeader, "encryption-secret")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusInternalServerError)
	}
	if got := response.Header().Get(requestIDHeader); got != "request-123" {
		t.Fatalf("%s = %q, want request-123", requestIDHeader, got)
	}
	record := decodeLogRecord(t, &logs)
	assertLogField(t, record, "msg", "http request panicked")
	assertLogField(t, record, "request_id", "request-123")
	assertLogField(t, record, "method", http.MethodGet)
	assertLogField(t, record, "route", "GET /v1/resources/{kind}/{id}")
	assertLogField(t, record, "status", float64(http.StatusInternalServerError))
	assertLogField(t, record, "panic_type", "string")
	if stack, _ := record["stack"].(string); stack == "" {
		t.Fatal("panic log is missing its stack")
	}
	for _, secret := range []string{
		"panic-secret-must-not-be-logged",
		"query-secret",
		"authorization-secret",
		"encryption-secret",
		"/v1/resources/profile/private",
	} {
		if strings.Contains(logs.String(), secret) {
			t.Fatalf("structured log leaked %q: %s", secret, logs.String())
		}
	}
}

func TestWithRecoveryLogsServerErrorsWithCorrelationFields(t *testing.T) {
	t.Parallel()

	var logs bytes.Buffer
	api := &API{logger: slog.New(slog.NewJSONHandler(&logs, nil))}
	handler := api.withRecovery(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Pattern = "GET /healthz"
		writeError(w, http.StatusServiceUnavailable, "database_unavailable", "database is unavailable")
	}))
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	request.Header.Set(requestIDHeader, "health-check-7")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	record := decodeLogRecord(t, &logs)
	assertLogField(t, record, "msg", "http request failed")
	assertLogField(t, record, "request_id", "health-check-7")
	assertLogField(t, record, "method", http.MethodGet)
	assertLogField(t, record, "route", "GET /healthz")
	assertLogField(t, record, "status", float64(http.StatusServiceUnavailable))
	if _, ok := record["duration_ms"]; !ok {
		t.Fatal("server-error log is missing duration_ms")
	}
}

func TestWithRecoveryReplacesUnsafeRequestIDWithoutLoggingSuccess(t *testing.T) {
	t.Parallel()

	var logs bytes.Buffer
	api := &API{logger: slog.New(slog.NewJSONHandler(&logs, nil))}
	handler := api.withRecovery(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	request.Header.Set(requestIDHeader, "unsafe request id\nsecret")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	requestID := response.Header().Get(requestIDHeader)
	if requestID == "" || requestID == "unsafe request id\nsecret" {
		t.Fatalf("generated %s = %q", requestIDHeader, requestID)
	}
	if logs.Len() != 0 {
		t.Fatalf("successful request unexpectedly logged: %s", logs.String())
	}
}

func decodeLogRecord(t *testing.T, logs *bytes.Buffer) map[string]any {
	t.Helper()
	var record map[string]any
	if err := json.Unmarshal(bytes.TrimSpace(logs.Bytes()), &record); err != nil {
		t.Fatalf("decode structured log: %v; log = %s", err, logs.String())
	}
	return record
}

func assertLogField(t *testing.T, record map[string]any, name string, want any) {
	t.Helper()
	if got := record[name]; got != want {
		t.Fatalf("log field %s = %#v, want %#v", name, got, want)
	}
}
