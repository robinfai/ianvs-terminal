package secure

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"

	"golang.org/x/crypto/argon2"

	"ianvs-terminal/backend/internal/model"
)

const (
	KeyContractVersion              = 1
	KeyDerivationFormat             = "argon2id-v1"
	CiphertextFormat                = "aes-256-gcm-v1"
	MaximumUserKeyBytes             = 1024
	minimumKeyLength                = 16
	maximumConcurrentKeyDerivations = 2
)

type keyDerivationParameters struct {
	time      uint32
	memoryKiB uint32
	threads   uint8
	keyLength uint32
}

var keyDerivationAdmission = newDerivationAdmission(maximumConcurrentKeyDerivations)

var (
	ErrKeyRequired       = errors.New("encryption key is required")
	ErrInvalidKey        = errors.New("encryption key is invalid")
	ErrWeakKey           = errors.New("encryption key must contain at least 16 bytes")
	ErrKeyTooLong        = fmt.Errorf("encryption key must not exceed %d bytes", MaximumUserKeyBytes)
	ErrKeyDerivationBusy = errors.New("encryption key derivation capacity is busy")
)

type derivationAdmission struct {
	slots chan struct{}
}

func newDerivationAdmission(capacity int) *derivationAdmission {
	return &derivationAdmission{slots: make(chan struct{}, capacity)}
}

func (a *derivationAdmission) run(operation func() []byte) ([]byte, error) {
	select {
	case a.slots <- struct{}{}:
		defer func() { <-a.slots }()
		return operation(), nil
	default:
		return nil, ErrKeyDerivationBusy
	}
}

func GenerateUserKey() (string, error) {
	value := make([]byte, 32)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate user key: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(value), nil
}

func ConfigureUserKey(user *model.User, secret string) ([]byte, error) {
	if err := ValidateUserKeyForConfiguration(secret); err != nil {
		return nil, err
	}
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return nil, fmt.Errorf("generate key salt: %w", err)
	}
	parameters, _ := keyDerivationParametersFor(KeyDerivationFormat)
	key, err := derive(secret, salt, parameters)
	if err != nil {
		return nil, err
	}
	user.KeyDerivation = KeyDerivationFormat
	user.KeySalt = base64.RawStdEncoding.EncodeToString(salt)
	user.KeyVerifier = verifier(key)
	return key, nil
}

func ValidateUserKeyForConfiguration(secret string) error {
	if len(secret) < minimumKeyLength {
		return ErrWeakKey
	}
	if len(secret) > MaximumUserKeyBytes {
		return ErrKeyTooLong
	}
	return nil
}

func VerifyUserKey(user model.User, secret string) ([]byte, error) {
	if secret == "" {
		return nil, ErrKeyRequired
	}
	if len(secret) > MaximumUserKeyBytes {
		return nil, ErrKeyTooLong
	}
	parameters, supported := keyDerivationParametersFor(user.KeyDerivation)
	if !supported || user.KeySalt == "" || user.KeyVerifier == "" {
		return nil, ErrKeyRequired
	}
	salt, err := base64.RawStdEncoding.DecodeString(user.KeySalt)
	if err != nil {
		return nil, fmt.Errorf("invalid stored key salt: %w", err)
	}
	key, err := derive(secret, salt, parameters)
	if err != nil {
		return nil, err
	}
	expected, err := base64.RawStdEncoding.DecodeString(user.KeyVerifier)
	if err != nil {
		return nil, fmt.Errorf("invalid stored key verifier: %w", err)
	}
	actual, err := base64.RawStdEncoding.DecodeString(verifier(key))
	if err != nil {
		return nil, fmt.Errorf("encode key verifier: %w", err)
	}
	if len(expected) != len(actual) || subtle.ConstantTimeCompare(expected, actual) != 1 {
		return nil, ErrInvalidKey
	}
	return key, nil
}

func Encrypt(key, cleartext []byte, associatedData string) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("create cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("create gcm: %w", err)
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", fmt.Errorf("generate nonce: %w", err)
	}
	sealed := aead.Seal(nil, nonce, cleartext, []byte(associatedData))
	envelope := append(nonce, sealed...)
	return base64.RawStdEncoding.EncodeToString(envelope), nil
}

func Decrypt(key []byte, encoded, associatedData string) ([]byte, error) {
	envelope, err := base64.RawStdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("decode ciphertext: %w", err)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create gcm: %w", err)
	}
	if len(envelope) < aead.NonceSize()+aead.Overhead() {
		return nil, errors.New("ciphertext envelope is too short")
	}
	nonce := envelope[:aead.NonceSize()]
	ciphertext := envelope[aead.NonceSize():]
	cleartext, err := aead.Open(nil, nonce, ciphertext, []byte(associatedData))
	if err != nil {
		return nil, errors.New("decrypt sensitive data: authentication failed")
	}
	return cleartext, nil
}

func AssociatedData(userID, kind, externalID string) string {
	return "ianvs-resource:v1:" + userID + ":" + kind + ":" + externalID
}

func keyDerivationParametersFor(format string) (keyDerivationParameters, bool) {
	switch format {
	case "argon2id-v1":
		// Published v1 parameters are immutable. A future cost change must add a
		// new format and retain this branch for existing accounts.
		return keyDerivationParameters{
			time:      3,
			memoryKiB: 64 * 1024,
			threads:   2,
			keyLength: 32,
		}, true
	default:
		return keyDerivationParameters{}, false
	}
}

func derive(
	secret string,
	salt []byte,
	parameters keyDerivationParameters,
) ([]byte, error) {
	return keyDerivationAdmission.run(func() []byte {
		return argon2.IDKey(
			[]byte(secret),
			salt,
			parameters.time,
			parameters.memoryKiB,
			parameters.threads,
			parameters.keyLength,
		)
	})
}

func verifier(key []byte) string {
	digest := hmac.New(sha256.New, key)
	_, _ = digest.Write([]byte("ianvs-user-key-verifier-v1"))
	return base64.RawStdEncoding.EncodeToString(digest.Sum(nil))
}
