package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"errors"
	"ianvs-terminal/backend/internal/model"
	"testing"
	"time"
)

func TestOAuthFirstLoginRequiresChoiceAndCrossLinkPreservesAccount(t *testing.T) {
	for _, first := range []string{"apple", "google"} {
		t.Run(first, func(t *testing.T) {
			s, db := operationContractService(t)
			ctx := context.Background()
			challenge := func() string {
				n, e := s.CreateAppleChallenge(ctx)
				if e != nil {
					t.Fatal(e)
				}
				return n
			}
			second := "google"
			if first == "google" {
				second = "apple"
			}
			input := OAuthLogin{Provider: first, Subject: "new-identity", Nonce: challenge(), AllowRegistration: true}
			if _, e := s.BeginOAuthLogin(ctx, input); !errors.Is(e, ErrOAuthChoiceRequired) {
				t.Fatal(e)
			}
			var count int64
			db.Model(&model.User{}).Count(&count)
			if count != 0 {
				t.Fatal("created an account before choice")
			}
			input.Action = "create"
			op, e := s.BeginOAuthLogin(ctx, input)
			if e != nil {
				t.Fatal(e)
			}
			original, e := s.CompleteLogin(ctx, op.OperationID)
			if e != nil {
				t.Fatal(e)
			}
			linked := OAuthLogin{Provider: second, Subject: "second-identity", Nonce: challenge(), Action: "link", LinkProvider: first, LinkSubject: input.Subject, LinkNonce: challenge()}
			op, e = s.BeginOAuthLogin(ctx, linked)
			if e != nil {
				t.Fatal(e)
			}
			result, e := s.CompleteLogin(ctx, op.OperationID)
			if e != nil || result.User.ID != original.User.ID {
				t.Fatalf("changed account: %v", e)
			}
			if _, e = s.BeginOAuthLogin(ctx, linked); !errors.Is(e, ErrAppleIdentity) {
				t.Fatalf("replayed proofs: %v", e)
			}
			linked.Nonce = challenge()
			linked.LinkNonce = challenge()
			linked.LinkSubject = "no-account"
			if _, e = s.BeginOAuthLogin(ctx, linked); !errors.Is(e, ErrOAuthHistoricalMissing) {
				t.Fatalf("linked nonexistent account: %v", e)
			}
			db.Model(&model.User{}).Count(&count)
			if count != 1 {
				t.Fatal("cross-link created duplicate account")
			}
		})
	}
}

func TestGoogleIdentityRequiresGoogleIssuerAudienceAndNonce(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	verifier := NewGoogleTokenVerifier()
	verifier.keys = map[string]*rsa.PublicKey{"test": &key.PublicKey}
	verifier.fetched = time.Now()
	nonce := operationContractID(t)
	claims := map[string]any{"iss": "https://accounts.google.com", "aud": "trail.apps.googleusercontent.com", "sub": "google-subject", "nonce": nonce, "iat": time.Now().Unix(), "exp": time.Now().Unix() + 300}
	verify := func() error {
		_, e := verifier.Verify(context.Background(), signAppleTestToken(t, key, "RS256", claims), nonce, []string{"trail.apps.googleusercontent.com"})
		return e
	}
	if err := verify(); err != nil {
		t.Fatal(err)
	}
	for field, invalid := range map[string]any{"iss": "https://appleid.apple.com", "aud": "another.apps.googleusercontent.com", "nonce": operationContractID(t), "exp": time.Now().Unix() - 1} {
		old := claims[field]
		claims[field] = invalid
		if err := verify(); err == nil {
			t.Fatalf("accepted invalid %s", field)
		}
		claims[field] = old
	}
}

func TestAuthenticatedOAuthLinkKeepsAccountAndRejectsTransfer(t *testing.T) {
	s, db := operationContractService(t)
	ctx := context.Background()
	challenge := func() string {
		n, e := s.CreateAppleChallenge(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return n
	}
	create := func(subject string) string {
		op, e := s.BeginOAuthLogin(ctx, OAuthLogin{Provider: "apple", Subject: subject, Nonce: challenge(), Action: "create", AllowRegistration: true})
		if e != nil {
			t.Fatal(e)
		}
		result, e := s.CompleteLogin(ctx, op.OperationID)
		if e != nil {
			t.Fatal(e)
		}
		return result.User.ID
	}
	first, second := create("first"), create("second")
	nonce := challenge()
	if e := s.LinkOAuthIdentity(ctx, first, "google", "google-first", nonce); e != nil {
		t.Fatal(e)
	}
	providers, e := s.LinkedProviders(ctx, first)
	if e != nil || len(providers) != 2 {
		t.Fatalf("providers=%v err=%v", providers, e)
	}
	if e := s.LinkOAuthIdentity(ctx, first, "google", "google-first", nonce); !errors.Is(e, ErrAppleIdentity) {
		t.Fatalf("replay accepted: %v", e)
	}
	if e := s.LinkOAuthIdentity(ctx, second, "google", "google-first", challenge()); !errors.Is(e, ErrAppleLinkConflict) {
		t.Fatalf("identity transfer accepted: %v", e)
	}
	if e := s.LinkOAuthIdentity(ctx, first, "google", "google-second", challenge()); !errors.Is(e, ErrAppleLinkConflict) {
		t.Fatalf("binding replacement accepted: %v", e)
	}
	providers, e = s.LinkedProviders(ctx, second)
	if e != nil || len(providers) != 1 || providers[0] != "apple" {
		t.Fatalf("other account changed: %v %v", providers, e)
	}
	var count int64
	db.Model(&model.User{}).Count(&count)
	if count != 2 {
		t.Fatal("link created an account")
	}
}
