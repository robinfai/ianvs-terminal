package auth

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"ianvs-terminal/backend/internal/model"
	"testing"
	"time"
)

func TestAppleTokenRequiresTrustedSignatureAndClaims(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	v := &AppleTokenVerifier{keys: map[string]*rsa.PublicKey{"test": &key.PublicKey}, fetched: time.Now()}
	nonce := operationContractID(t)
	for _, tc := range []struct {
		name  string
		alter func(map[string]any)
		valid bool
	}{
		{"valid", func(map[string]any) {}, true},
		{"wrong audience", func(c map[string]any) { c["aud"] = "another.app" }, false},
		{"wrong issuer", func(c map[string]any) { c["iss"] = "https://attacker.example" }, false},
		{"wrong nonce", func(c map[string]any) { c["nonce"] = "other" }, false},
		{"expired", func(c map[string]any) { c["exp"] = time.Now().Unix() - 1 }, false},
		{"future issued", func(c map[string]any) { c["iat"] = time.Now().Unix() + 600 }, false},
		{"missing subject", func(c map[string]any) { delete(c, "sub") }, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			claims := map[string]any{"iss": "https://appleid.apple.com", "aud": "work.ianvs.trail", "sub": "apple-user", "nonce": nonce, "iat": time.Now().Unix(), "exp": time.Now().Unix() + 300}
			tc.alter(claims)
			token := signAppleTestToken(t, key, "RS256", claims)
			subject, err := v.Verify(context.Background(), token, nonce, []string{"work.ianvs.trail"})
			if tc.valid {
				if err != nil || subject != "apple-user" {
					t.Fatalf("%s %v", subject, err)
				}
			} else if !errors.Is(err, ErrAppleIdentity) {
				t.Fatalf("accepted invalid claims: %v", err)
			}
			if _, err := v.Verify(context.Background(), token+"tampered", nonce, []string{"work.ianvs.trail"}); err == nil {
				t.Fatal("accepted tampered signature")
			}
		})
	}
	if _, err := v.Verify(context.Background(), signAppleTestToken(t, key, "none", map[string]any{}), nonce, []string{"work.ianvs.trail"}); err == nil {
		t.Fatal("accepted unsigned algorithm")
	}
}
func signAppleTestToken(t *testing.T, key *rsa.PrivateKey, alg string, claims map[string]any) string {
	t.Helper()
	header, _ := json.Marshal(map[string]string{"alg": alg, "kid": "test"})
	payload, _ := json.Marshal(claims)
	body := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	digest := sha256.Sum256([]byte(body))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return body + "." + base64.RawURLEncoding.EncodeToString(sig)
}
func TestAppleBindingPreservesExistingAccountAndRejectsReplayAndConflicts(t *testing.T) {
	s, db := operationContractService(t)
	ctx := context.Background()
	user := createOperationContractUser(t, db, "historical")
	challenge := func() string {
		t.Helper()
		n, e := s.CreateAppleChallenge(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return n
	}
	nonce := challenge()
	if _, err := s.BeginAppleLogin(ctx, "apple-a", nonce, "historical", "wrong-password-long", false); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatal(err)
	}
	op, err := s.BeginAppleLogin(ctx, "apple-a", nonce, "historical", operationContractPassword, false)
	if err != nil {
		t.Fatal(err)
	}
	assertOperationTokenCount(t, db, op.OperationID, 0)
	session, err := s.CompleteLogin(ctx, op.OperationID)
	if err != nil || session.User.ID != user.ID {
		t.Fatalf("changed account: %+v %v", session.User, err)
	}
	if _, err := s.BeginAppleLogin(ctx, "apple-a", nonce, "", "", false); !errors.Is(err, ErrAppleIdentity) {
		t.Fatalf("replayed challenge: %v", err)
	}
	op, err = s.BeginAppleLogin(ctx, "apple-a", challenge(), "", "", false)
	if err != nil {
		t.Fatal(err)
	}
	session, err = s.CompleteLogin(ctx, op.OperationID)
	if err != nil || session.User.ID != user.ID {
		t.Fatalf("Apple login lost historical identity: %v", err)
	}
	if _, err := s.BeginAppleLogin(ctx, "apple-b", challenge(), "historical", operationContractPassword, false); !errors.Is(err, ErrAppleLinkConflict) {
		t.Fatalf("replaced link: %v", err)
	}
	createOperationContractUser(t, db, "another")
	if _, err := s.BeginAppleLogin(ctx, "apple-a", challenge(), "another", operationContractPassword, false); !errors.Is(err, ErrAppleLinkConflict) {
		t.Fatalf("moved account: %v", err)
	}
	var count int64
	db.Model(&model.User{}).Count(&count)
	if count != 2 {
		t.Fatalf("unexpected accounts: %d", count)
	}
}
func TestAppleRegistrationAndExpiredChallenge(t *testing.T) {
	s, db := operationContractService(t)
	ctx := context.Background()
	nonce, err := s.CreateAppleChallenge(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.BeginAppleLogin(ctx, "new", nonce, "", "", false); !errors.Is(err, ErrAppleRegistrationDisabled) {
		t.Fatal(err)
	}
	op, err := s.BeginAppleLogin(ctx, "new", nonce, "", "", true)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CancelOperation(ctx, op.OperationID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteLogin(ctx, op.OperationID); !errors.Is(err, ErrOperationCanceled) {
		t.Fatal(err)
	}
	nonce, err = s.CreateAppleChallenge(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Model(&model.Setting{}).Where("`key` = ?", appleChallengePrefix+hashToken(nonce)).Update("created_at", time.Now().UTC().Add(-10*time.Minute)).Error; err != nil {
		t.Fatal(err)
	}
	if _, err := s.BeginAppleLogin(ctx, "new", nonce, "", "", true); !errors.Is(err, ErrAppleIdentity) {
		t.Fatal(err)
	}
}
