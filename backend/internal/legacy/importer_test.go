package legacy_test

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/legacy"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/store"
)

func TestImporterMovesKnownProfileSecretsOutOfPlainJSON(t *testing.T) {
	ctx := context.Background()
	legacyDirectory := t.TempDir()
	legacyProfileKey := make([]byte, 32)
	for index := range legacyProfileKey {
		legacyProfileKey[index] = byte(index + 1)
	}
	profiles := map[string]any{
		"schemaVersion": 4,
		"profiles": []any{
			map[string]any{
				"id":   "work",
				"name": "Work",
				"connection": map[string]any{
					"type":                 "ssh",
					"host":                 "example.com",
					"password":             "plaintext-password",
					"privateKeyPassphrase": "key-passphrase",
					"proxyJumpProfiles": []any{
						map[string]any{"host": "jump.example.com", "password": "jump-password"},
					},
				},
			},
			map[string]any{
				"id":   "encrypted-work",
				"name": "Encrypted work",
				"connection": map[string]any{
					"type": "ssh",
					"host": "encrypted.example.com",
					"encryptedSecrets": map[string]any{
						"format":   "ianvs-profile-secrets-v1",
						"password": legacyEnvelope(t, legacyProfileKey, "encrypted-work", "password", "keychain-password"),
					},
				},
			},
		},
	}
	encodedProfiles, err := json.Marshal(profiles)
	if err != nil {
		t.Fatalf("encode profiles fixture: %v", err)
	}
	if err := os.WriteFile(filepath.Join(legacyDirectory, "ianvs_profiles.json"), encodedProfiles, 0o600); err != nil {
		t.Fatalf("write profiles fixture: %v", err)
	}
	if err := os.WriteFile(filepath.Join(legacyDirectory, "ianvs_config.json"), []byte(`{"schemaVersion":2,"defaultProfileId":"work"}`), 0o600); err != nil {
		t.Fatalf("write config fixture: %v", err)
	}

	cfg := config.Config{
		Mode:           config.ModeLocal,
		DatabaseDriver: "sqlite",
		DatabaseDSN:    filepath.Join(t.TempDir(), "import.db"),
		TokenTTL:       time.Hour,
	}
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("database.Open() error = %v", err)
	}
	resourceStore, err := store.New(ctx, db)
	if err != nil {
		t.Fatalf("store.New() error = %v", err)
	}
	authService := auth.New(db, time.Hour)
	user, _, err := authService.SetupLocalKey(ctx, "legacy-import-encryption-key")
	if err != nil {
		t.Fatalf("SetupLocalKey() error = %v", err)
	}
	key, err := authService.VerifyKey(user, "legacy-import-encryption-key")
	if err != nil {
		t.Fatalf("VerifyKey() error = %v", err)
	}

	importer, err := legacy.New(resourceStore, base64.StdEncoding.EncodeToString(legacyProfileKey))
	if err != nil {
		t.Fatalf("legacy.New() error = %v", err)
	}
	report, err := importer.Import(ctx, user, key, legacyDirectory)
	if err != nil {
		t.Fatalf("Import() error = %v", err)
	}
	if report.Merge.Created != 3 {
		t.Fatalf("Import() report = %#v", report)
	}
	profile, err := resourceStore.Get(ctx, user, key, "profile", "work", true)
	if err != nil {
		t.Fatalf("Get(profile) error = %v", err)
	}
	if strings.Contains(string(profile.Data), "plaintext-password") || strings.Contains(string(profile.Data), "key-passphrase") || strings.Contains(string(profile.Data), "jump-password") {
		t.Fatalf("plain profile contains a secret: %s", profile.Data)
	}
	var sensitive map[string]any
	if err := json.Unmarshal(profile.Sensitive, &sensitive); err != nil {
		t.Fatalf("decode sensitive profile: %v", err)
	}
	connection, _ := sensitive["connection"].(map[string]any)
	if connection["password"] != "plaintext-password" || connection["privateKeyPassphrase"] != "key-passphrase" {
		t.Fatalf("sensitive profile = %#v", sensitive)
	}

	var persisted model.Resource
	if err := db.Where("kind = ? AND external_id = ?", "profile", "work").First(&persisted).Error; err != nil {
		t.Fatalf("load persisted profile: %v", err)
	}
	if strings.Contains(persisted.PlainJSON, "plaintext-password") || strings.Contains(persisted.SensitiveCiphertext, "plaintext-password") {
		t.Fatal("legacy plaintext password remained visible in database")
	}
	encryptedProfile, err := resourceStore.Get(ctx, user, key, "profile", "encrypted-work", true)
	if err != nil {
		t.Fatalf("Get(encrypted profile) error = %v", err)
	}
	if !strings.Contains(string(encryptedProfile.Sensitive), "keychain-password") || strings.Contains(string(encryptedProfile.Data), "keychain-password") {
		t.Fatalf("encrypted profile migration = data %s, sensitive %s", encryptedProfile.Data, encryptedProfile.Sensitive)
	}
}

func legacyEnvelope(
	t *testing.T,
	key []byte,
	profileID, field, value string,
) map[string]any {
	t.Helper()
	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatalf("aes.NewCipher() error = %v", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		t.Fatalf("cipher.NewGCM() error = %v", err)
	}
	nonce := make([]byte, aead.NonceSize())
	for index := range nonce {
		nonce[index] = byte(index + 10)
	}
	sealed := aead.Seal(
		nil,
		nonce,
		[]byte(value),
		[]byte("ianvs:ssh-profile:v1:"+profileID+":"+field),
	)
	ciphertext := sealed[:len(sealed)-aead.Overhead()]
	mac := sealed[len(sealed)-aead.Overhead():]
	return map[string]any{
		"schemaVersion": 1,
		"algorithm":     "aes-256-gcm",
		"nonce":         base64.StdEncoding.EncodeToString(nonce),
		"ciphertext":    base64.StdEncoding.EncodeToString(ciphertext),
		"mac":           base64.StdEncoding.EncodeToString(mac),
	}
}
