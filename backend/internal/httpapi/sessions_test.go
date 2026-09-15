package httpapi_test

import (
	"context"
	"encoding/json"
	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"net/http"
	"strings"
	"testing"
)

func TestSessionHTTPManagementIsOwnerScoped(t *testing.T) {
	cfg, db, h := testAPI(t, config.ModeRemote)
	s := auth.New(db, cfg.TokenTTL)
	ctx := context.Background()
	p, err := s.BeginRegister(ctx, "session-owner", "session-password")
	if err != nil {
		t.Fatal(err)
	}
	token, err := s.CompleteRegister(ctx, p.OperationID)
	if err != nil {
		t.Fatal(err)
	}
	headers := map[string]string{"Authorization": "Bearer " + token.Token}
	if r := request(t, h, http.MethodGet, "/v1/auth/sessions", nil, nil); r.Code != 401 {
		t.Fatalf("anonymous status %d", r.Code)
	}
	r := request(t, h, http.MethodGet, "/v1/auth/sessions", nil, headers)
	if r.Code != 200 {
		t.Fatal(r.Body.String())
	}
	if strings.Contains(r.Body.String(), token.Token) || strings.Contains(r.Body.String(), "token_hash") {
		t.Fatal("secret leaked")
	}
	var list struct {
		Sessions []auth.SessionView `json:"sessions"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &list); err != nil {
		t.Fatal(err)
	}
	if len(list.Sessions) != 1 || !list.Sessions[0].Current {
		t.Fatal(r.Body.String())
	}
	id := list.Sessions[0].ID
	p, err = s.BeginRegister(ctx, "different-owner", "session-password")
	if err != nil {
		t.Fatal(err)
	}
	other, err := s.CompleteRegister(ctx, p.OperationID)
	if err != nil {
		t.Fatal(err)
	}
	r = request(t, h, http.MethodDelete, "/v1/auth/sessions/"+id, nil, map[string]string{"Authorization": "Bearer " + other.Token})
	if r.Code != 204 {
		t.Fatal(r.Code)
	}
	if r := request(t, h, http.MethodGet, "/v1/me", nil, headers); r.Code != 200 {
		t.Fatal("foreign deletion succeeded")
	}
	r = request(t, h, http.MethodDelete, "/v1/auth/sessions/"+id, nil, headers)
	if r.Code != 204 {
		t.Fatal(r.Code)
	}
	if r := request(t, h, http.MethodGet, "/v1/me", nil, headers); r.Code != 401 {
		t.Fatal("token not revoked")
	}
}
