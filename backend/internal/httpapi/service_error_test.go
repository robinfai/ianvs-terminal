package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"ianvs-terminal/backend/internal/auth"
)

func TestWriteServiceErrorReturnsRetryablePasswordHashCapacityContract(t *testing.T) {
	response := httptest.NewRecorder()
	new(API).writeServiceError(response, auth.ErrPasswordHashBusy)

	if response.Code != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusTooManyRequests)
	}
	if response.Header().Get("Retry-After") != "1" {
		t.Fatalf("Retry-After = %q, want 1", response.Header().Get("Retry-After"))
	}
	if !strings.Contains(response.Body.String(), `"code":"password_hash_busy"`) {
		t.Fatalf("response did not contain typed password capacity code: %s", response.Body.String())
	}
}
