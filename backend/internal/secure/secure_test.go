package secure_test

import (
	"bytes"
	"errors"
	"strings"
	"testing"

	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/secure"
)

func TestUserKeyVerifierAndAuthenticatedEncryption(t *testing.T) {
	t.Parallel()

	user := model.User{ID: "user-1"}
	key, err := secure.ConfigureUserKey(&user, "user-created-key-with-enough-entropy")
	if err != nil {
		t.Fatalf("ConfigureUserKey() error = %v", err)
	}
	if user.KeySalt == "" || user.KeyVerifier == "" {
		t.Fatal("ConfigureUserKey() did not persist verifier metadata")
	}
	verified, err := secure.VerifyUserKey(user, "user-created-key-with-enough-entropy")
	if err != nil {
		t.Fatalf("VerifyUserKey() error = %v", err)
	}
	if !bytes.Equal(key, verified) {
		t.Fatal("VerifyUserKey() derived a different key")
	}
	if _, err := secure.VerifyUserKey(user, "different-user-created-key"); !errors.Is(err, secure.ErrInvalidKey) {
		t.Fatalf("VerifyUserKey(wrong) error = %v, want ErrInvalidKey", err)
	}

	aad := secure.AssociatedData(user.ID, "profile", "work")
	ciphertext, err := secure.Encrypt(key, []byte(`{"password":"secret"}`), aad)
	if err != nil {
		t.Fatalf("Encrypt() error = %v", err)
	}
	cleartext, err := secure.Decrypt(key, ciphertext, aad)
	if err != nil {
		t.Fatalf("Decrypt() error = %v", err)
	}
	if string(cleartext) != `{"password":"secret"}` {
		t.Fatalf("Decrypt() = %s", cleartext)
	}
	if _, err := secure.Decrypt(key, ciphertext, secure.AssociatedData(user.ID, "profile", "other")); err == nil {
		t.Fatal("Decrypt() accepted ciphertext under different associated data")
	}
}

func TestConfigureUserKeyRejectsShortSecret(t *testing.T) {
	t.Parallel()

	user := model.User{}
	if _, err := secure.ConfigureUserKey(&user, "too-short"); !errors.Is(err, secure.ErrWeakKey) {
		t.Fatalf("ConfigureUserKey() error = %v, want ErrWeakKey", err)
	}
}

func TestUserKeyOperationsRejectOversizedSecretsBeforeDerivation(t *testing.T) {
	t.Parallel()

	oversized := strings.Repeat("x", secure.MaximumUserKeyBytes+1)
	user := model.User{}
	if _, err := secure.ConfigureUserKey(&user, oversized); !errors.Is(err, secure.ErrKeyTooLong) {
		t.Fatalf("ConfigureUserKey(oversized) error = %v, want ErrKeyTooLong", err)
	}
	user.KeyDerivation = secure.KeyDerivationFormat
	user.KeySalt = "not-used"
	user.KeyVerifier = "not-used"
	if _, err := secure.VerifyUserKey(user, oversized); !errors.Is(err, secure.ErrKeyTooLong) {
		t.Fatalf("VerifyUserKey(oversized) error = %v, want ErrKeyTooLong", err)
	}
}
