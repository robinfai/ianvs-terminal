package legacy

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/store"
)

var safeResourceID = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,190}$`)

type Importer struct {
	store            *store.Store
	legacyProfileKey []byte
}

type Report struct {
	Directory     string            `json:"directory"`
	ImportedFiles []string          `json:"imported_files"`
	MissingFiles  []string          `json:"missing_files"`
	Merge         store.MergeReport `json:"merge"`
}

func New(resourceStore *store.Store, encodedLegacyProfileKey string) (*Importer, error) {
	legacyProfileKey, err := decodeLegacyProfileKey(encodedLegacyProfileKey)
	if err != nil {
		return nil, err
	}
	return &Importer{store: resourceStore, legacyProfileKey: legacyProfileKey}, nil
}

func (i *Importer) Import(
	ctx context.Context,
	user model.User,
	key []byte,
	directory string,
) (Report, error) {
	directory = filepath.Clean(strings.TrimSpace(directory))
	if directory == "." || directory == "" {
		return Report{}, errors.New("legacy data directory is required")
	}
	info, err := os.Stat(directory)
	if err != nil {
		return Report{}, fmt.Errorf("open legacy data directory: %w", err)
	}
	if !info.IsDir() {
		return Report{}, errors.New("legacy data path is not a directory")
	}

	report := Report{Directory: directory}
	resources := make([]store.ResourceView, 0)
	loaders := []func(string) ([]store.ResourceView, bool, error){
		func(dir string) ([]store.ResourceView, bool, error) {
			return loadProfiles(dir, i.legacyProfileKey)
		},
		func(dir string) ([]store.ResourceView, bool, error) {
			return loadDocument(dir, "ianvs_preferences.json", "config", "preferences", false)
		},
		func(dir string) ([]store.ResourceView, bool, error) {
			return loadDocument(dir, "ianvs_config.json", "config", "local-terminal", false)
		},
		func(dir string) ([]store.ResourceView, bool, error) {
			return loadDocument(dir, "ianvs_terminal_layout.json", "session", "layout", true)
		},
		func(dir string) ([]store.ResourceView, bool, error) {
			return loadCollection(dir, "ianvs_themes.json", "theme")
		},
		func(dir string) ([]store.ResourceView, bool, error) {
			return loadCollection(dir, "ianvs_layout_templates.json", "layout_template")
		},
		func(dir string) ([]store.ResourceView, bool, error) {
			return loadDocument(dir, "ianvs_recent_items.json", "recent_items", "default", true)
		},
		func(dir string) ([]store.ResourceView, bool, error) {
			return loadDocument(dir, "ianvs_paste_history.json", "paste_history", "default", true)
		},
	}
	fileNames := []string{
		"ianvs_profiles.json",
		"ianvs_preferences.json",
		"ianvs_config.json",
		"ianvs_terminal_layout.json",
		"ianvs_themes.json",
		"ianvs_layout_templates.json",
		"ianvs_recent_items.json",
		"ianvs_paste_history.json",
	}
	for index, loader := range loaders {
		loaded, found, err := loader(directory)
		if err != nil {
			return Report{}, err
		}
		if !found {
			report.MissingFiles = append(report.MissingFiles, fileNames[index])
			continue
		}
		report.ImportedFiles = append(report.ImportedFiles, fileNames[index])
		resources = append(resources, loaded...)
	}

	sourceDigest := sha256.Sum256([]byte(directory))
	merge, err := i.store.Merge(ctx, user, key, store.MergeRequest{
		SchemaVersion:  1,
		SourceID:       "legacy-json-" + hex.EncodeToString(sourceDigest[:8]),
		ConflictPolicy: store.SourceWins,
		Resources:      resources,
	})
	if err != nil {
		return Report{}, err
	}
	report.Merge = merge
	return report, nil
}

func loadProfiles(directory string, legacyProfileKey []byte) ([]store.ResourceView, bool, error) {
	path := filepath.Join(directory, "ianvs_profiles.json")
	raw, info, found, err := readFile(path)
	if err != nil || !found {
		return nil, found, err
	}
	var document map[string]any
	if err := json.Unmarshal(raw, &document); err != nil {
		return nil, true, fmt.Errorf("decode %s: %w", path, err)
	}
	rawProfiles, ok := document["profiles"].([]any)
	if !ok {
		rawProfiles, _ = document["Profiles"].([]any)
	}
	resources := make([]store.ResourceView, 0, len(rawProfiles))
	for index, rawProfile := range rawProfiles {
		profile, ok := rawProfile.(map[string]any)
		if !ok {
			continue
		}
		idValue, _ := profile["id"].(string)
		if strings.TrimSpace(idValue) == "" {
			idValue, _ = profile["Guid"].(string)
		}
		id := stableResourceID(idValue, fmt.Sprintf("profile-%d", index))
		plain, sensitive, err := splitProfileSecrets(profile, idValue, legacyProfileKey)
		if err != nil {
			return nil, true, fmt.Errorf("decrypt legacy profile %s: %w", id, err)
		}
		plainJSON, err := json.Marshal(plain)
		if err != nil {
			return nil, true, fmt.Errorf("encode profile %s: %w", id, err)
		}
		view := migrationView("profile", id, plainJSON, info)
		if len(sensitive) != 0 {
			sensitiveJSON, err := json.Marshal(sensitive)
			if err != nil {
				return nil, true, fmt.Errorf("encode sensitive profile fields %s: %w", id, err)
			}
			view.Sensitive = sensitiveJSON
			view.HasSensitive = true
		}
		resources = append(resources, view)
	}
	return resources, true, nil
}

func loadDocument(
	directory, fileName, kind, id string,
	sensitive bool,
) ([]store.ResourceView, bool, error) {
	path := filepath.Join(directory, fileName)
	raw, info, found, err := readFile(path)
	if err != nil || !found {
		return nil, found, err
	}
	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		return nil, true, fmt.Errorf("decode %s: %w", path, err)
	}
	canonical, err := json.Marshal(value)
	if err != nil {
		return nil, true, fmt.Errorf("encode %s: %w", path, err)
	}
	if !sensitive {
		return []store.ResourceView{migrationView(kind, id, canonical, info)}, true, nil
	}
	metadata, _ := json.Marshal(map[string]string{"legacy_file": fileName})
	view := migrationView(kind, id, metadata, info)
	view.Sensitive = canonical
	view.HasSensitive = true
	return []store.ResourceView{view}, true, nil
}

func loadCollection(directory, fileName, kind string) ([]store.ResourceView, bool, error) {
	path := filepath.Join(directory, fileName)
	raw, info, found, err := readFile(path)
	if err != nil || !found {
		return nil, found, err
	}
	var values []any
	if err := json.Unmarshal(raw, &values); err != nil {
		return nil, true, fmt.Errorf("decode %s: %w", path, err)
	}
	resources := make([]store.ResourceView, 0, len(values))
	for index, rawValue := range values {
		value, ok := rawValue.(map[string]any)
		if !ok {
			continue
		}
		rawID, _ := value["id"].(string)
		id := stableResourceID(rawID, fmt.Sprintf("%s-%d", kind, index))
		data, err := json.Marshal(value)
		if err != nil {
			return nil, true, fmt.Errorf("encode %s %s: %w", kind, id, err)
		}
		resources = append(resources, migrationView(kind, id, data, info))
	}
	return resources, true, nil
}

func splitProfileSecrets(
	profile map[string]any,
	profileID string,
	legacyProfileKey []byte,
) (map[string]any, map[string]any, error) {
	plain := cloneMap(profile)
	sensitive := make(map[string]any)
	connection, ok := plain["connection"].(map[string]any)
	if !ok {
		return plain, sensitive, nil
	}
	sensitiveConnection := make(map[string]any)
	for _, field := range []string{
		"password",
		"privateKeyPassphrase",
		"x11AuthCookie",
	} {
		if value, found := connection[field]; found {
			sensitiveConnection[field] = value
			delete(connection, field)
		}
	}
	if encrypted, found := connection["encryptedSecrets"]; found {
		delete(connection, "encryptedSecrets")
		remaining, decrypted, err := decryptLegacyEncryptedSecrets(
			profileID,
			encrypted,
			legacyProfileKey,
		)
		if err != nil {
			return nil, nil, err
		}
		for field, value := range decrypted {
			sensitiveConnection[field] = value
		}
		if remaining != nil {
			sensitiveConnection["encryptedSecrets"] = remaining
		}
	}
	if jumps, ok := connection["proxyJumpProfiles"].([]any); ok {
		sensitiveJumps := make([]any, len(jumps))
		hasJumpSecret := false
		for index, rawJump := range jumps {
			jumpSecrets := make(map[string]any)
			jump, ok := rawJump.(map[string]any)
			if ok {
				for _, field := range []string{"password", "privateKeyPassphrase"} {
					if value, found := jump[field]; found {
						jumpSecrets[field] = value
						delete(jump, field)
						hasJumpSecret = true
					}
				}
			}
			sensitiveJumps[index] = jumpSecrets
		}
		if hasJumpSecret {
			sensitiveConnection["proxyJumpProfiles"] = sensitiveJumps
		}
	}
	if len(sensitiveConnection) != 0 {
		sensitive["connection"] = sensitiveConnection
	}
	return plain, sensitive, nil
}

func decryptLegacyEncryptedSecrets(
	profileID string,
	raw any,
	key []byte,
) (remaining map[string]any, decrypted map[string]any, err error) {
	encrypted, ok := raw.(map[string]any)
	if !ok || len(key) == 0 || encrypted["format"] != "ianvs-profile-secrets-v1" {
		if value, ok := raw.(map[string]any); ok {
			return value, nil, nil
		}
		return map[string]any{"value": raw}, nil, nil
	}
	remaining = cloneMap(encrypted)
	decrypted = make(map[string]any)
	for _, field := range []string{"password", "privateKeyPassphrase", "x11AuthCookie"} {
		envelope, found := encrypted[field]
		if !found {
			continue
		}
		cleartext, err := decryptLegacyEnvelope(key, profileID, field, envelope)
		if err != nil {
			return nil, nil, fmt.Errorf("%s: %w", field, err)
		}
		decrypted[field] = cleartext
		delete(remaining, field)
	}
	if len(remaining) == 1 && remaining["format"] == "ianvs-profile-secrets-v1" {
		remaining = nil
	}
	return remaining, decrypted, nil
}

func decryptLegacyEnvelope(key []byte, profileID, field string, raw any) (string, error) {
	envelope, ok := raw.(map[string]any)
	if !ok || envelope["schemaVersion"] != float64(1) || envelope["algorithm"] != "aes-256-gcm" {
		return "", errors.New("unsupported encrypted secret envelope")
	}
	nonce, err := decodeEnvelopePart(envelope, "nonce")
	if err != nil {
		return "", err
	}
	ciphertext, err := decodeEnvelopePart(envelope, "ciphertext")
	if err != nil {
		return "", err
	}
	mac, err := decodeEnvelopePart(envelope, "mac")
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("create legacy cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("create legacy gcm: %w", err)
	}
	if len(nonce) != aead.NonceSize() || len(mac) != aead.Overhead() {
		return "", errors.New("legacy encrypted secret has invalid nonce or mac length")
	}
	sealed := append(ciphertext, mac...)
	cleartext, err := aead.Open(
		nil,
		nonce,
		sealed,
		[]byte("ianvs:ssh-profile:v1:"+profileID+":"+field),
	)
	if err != nil {
		return "", errors.New("legacy encrypted secret authentication failed")
	}
	return string(cleartext), nil
}

func decodeEnvelopePart(envelope map[string]any, field string) ([]byte, error) {
	value, ok := envelope[field].(string)
	if !ok || value == "" {
		return nil, fmt.Errorf("legacy encrypted secret %s is missing", field)
	}
	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return nil, fmt.Errorf("decode legacy encrypted secret %s: %w", field, err)
	}
	return decoded, nil
}

func decodeLegacyProfileKey(encoded string) ([]byte, error) {
	if strings.TrimSpace(encoded) == "" {
		return nil, nil
	}
	key, err := base64.StdEncoding.DecodeString(strings.TrimSpace(encoded))
	if err != nil {
		key, err = base64.RawStdEncoding.DecodeString(strings.TrimSpace(encoded))
	}
	if err != nil || len(key) != 32 {
		return nil, errors.New("IANVS_LEGACY_PROFILE_KEY must be a base64-encoded 32-byte key")
	}
	return key, nil
}

func cloneMap(source map[string]any) map[string]any {
	raw, _ := json.Marshal(source)
	var cloned map[string]any
	_ = json.Unmarshal(raw, &cloned)
	return cloned
}

func migrationView(kind, id string, data []byte, info os.FileInfo) store.ResourceView {
	revision := info.ModTime().UTC().UnixNano()
	if revision <= 0 {
		revision = 1
	}
	return store.ResourceView{
		ID:              id,
		Kind:            kind,
		Data:            data,
		Revision:        1,
		SourceRevision:  revision,
		SourceUpdatedAt: info.ModTime().UTC(),
	}
}

func stableResourceID(value, fallback string) string {
	value = strings.TrimSpace(value)
	if safeResourceID.MatchString(value) {
		return value
	}
	if value == "" {
		value = fallback
	}
	digest := sha256.Sum256([]byte(value))
	return "legacy-" + hex.EncodeToString(digest[:16])
}

func readFile(path string) ([]byte, os.FileInfo, bool, error) {
	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil, false, nil
	}
	if err != nil {
		return nil, nil, false, fmt.Errorf("inspect %s: %w", path, err)
	}
	if !info.Mode().IsRegular() {
		return nil, nil, true, fmt.Errorf("legacy data path is not a regular file: %s", path)
	}
	if info.Size() > 8<<20 {
		return nil, nil, true, fmt.Errorf("legacy data file exceeds 8 MiB: %s", path)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, true, fmt.Errorf("read %s: %w", path, err)
	}
	return raw, info, true, nil
}
