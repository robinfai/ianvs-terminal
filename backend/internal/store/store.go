package store

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
	"time"

	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/identity"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/secure"
)

const (
	serverIDSetting       = "server_id"
	maxResourceDataBytes  = 4 << 20
	maxMigrationResources = 2000
)

var (
	ErrNotFound         = errors.New("resource not found")
	ErrRevisionConflict = errors.New("resource revision conflict")
	ErrInvalidResource  = errors.New("invalid resource")
	resourcePartPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]*$`)
)

type Store struct {
	db       *gorm.DB
	serverID string
}

type WriteInput struct {
	Data             json.RawMessage
	Sensitive        json.RawMessage
	SensitivePresent bool
	ClearSensitive   bool
	ExpectedRevision *int64
}

type ResourceView struct {
	ID              string          `json:"id"`
	Kind            string          `json:"kind"`
	Data            json.RawMessage `json:"data"`
	Sensitive       json.RawMessage `json:"sensitive,omitempty"`
	HasSensitive    bool            `json:"has_sensitive"`
	Revision        int64           `json:"revision"`
	SourceID        string          `json:"source_id"`
	SourceRevision  int64           `json:"source_revision"`
	SourceUpdatedAt time.Time       `json:"source_updated_at"`
	Deleted         bool            `json:"deleted"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
}

type ExportBundle struct {
	SchemaVersion int            `json:"schema_version"`
	SourceID      string         `json:"source_id"`
	ExportedAt    time.Time      `json:"exported_at"`
	Resources     []ResourceView `json:"resources"`
}

type ConflictPolicy string

const (
	PreserveDestination ConflictPolicy = "preserve_destination"
	SourceWins          ConflictPolicy = "source_wins"
	NewerWins           ConflictPolicy = "newer_wins"
)

type MergeRequest struct {
	SchemaVersion    int            `json:"schema_version"`
	SourceID         string         `json:"source_id"`
	ExportedAt       time.Time      `json:"exported_at,omitempty"`
	ConflictPolicy   ConflictPolicy `json:"conflict_policy"`
	PropagateDeletes bool           `json:"propagate_deletes"`
	Resources        []ResourceView `json:"resources"`
}

type MergeItemResult struct {
	Kind   string `json:"kind"`
	ID     string `json:"id"`
	Status string `json:"status"`
	Reason string `json:"reason,omitempty"`
}

type MergeReport struct {
	Created   int               `json:"created"`
	Updated   int               `json:"updated"`
	Deleted   int               `json:"deleted"`
	Skipped   int               `json:"skipped"`
	Conflicts int               `json:"conflicts"`
	Results   []MergeItemResult `json:"results"`
}

func New(ctx context.Context, db *gorm.DB) (*Store, error) {
	serverID, err := ensureServerID(ctx, db)
	if err != nil {
		return nil, err
	}
	return &Store{db: db, serverID: serverID}, nil
}

func (s *Store) DB() *gorm.DB { return s.db }

func (s *Store) ServerID() string { return s.serverID }

func (s *Store) Put(
	ctx context.Context,
	user model.User,
	key []byte,
	kind, externalID string,
	input WriteInput,
) (ResourceView, error) {
	if err := validateResourceKey(kind, externalID); err != nil {
		return ResourceView{}, err
	}
	plain, err := canonicalJSON(input.Data, false)
	if err != nil {
		return ResourceView{}, fmt.Errorf("%w: data: %v", ErrInvalidResource, err)
	}
	var sensitive []byte
	if input.SensitivePresent {
		if len(key) == 0 {
			return ResourceView{}, secure.ErrKeyRequired
		}
		sensitive, err = canonicalJSON(input.Sensitive, true)
		if err != nil {
			return ResourceView{}, fmt.Errorf("%w: sensitive: %v", ErrInvalidResource, err)
		}
	}

	var saved model.Resource
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var existing model.Resource
		queryErr := tx.Where(
			"user_id = ? AND kind = ? AND external_id = ?",
			user.ID,
			kind,
			externalID,
		).First(&existing).Error
		now := time.Now().UTC()
		if errors.Is(queryErr, gorm.ErrRecordNotFound) {
			id, idErr := identity.UUID()
			if idErr != nil {
				return idErr
			}
			saved = model.Resource{
				ID:              id,
				UserID:          user.ID,
				Kind:            kind,
				ExternalID:      externalID,
				PlainJSON:       string(plain),
				Revision:        1,
				SourceID:        s.serverID,
				SourceRevision:  1,
				OriginUpdatedAt: now,
			}
			if input.SensitivePresent && !isJSONNull(sensitive) {
				if err := encryptSensitive(&saved, key, sensitive); err != nil {
					return err
				}
			}
			return tx.Create(&saved).Error
		}
		if queryErr != nil {
			return queryErr
		}
		if input.ExpectedRevision != nil && existing.Revision != *input.ExpectedRevision {
			return ErrRevisionConflict
		}

		saved = existing
		saved.PlainJSON = string(plain)
		saved.Deleted = false
		saved.DeletedAt = nil
		saved.Revision++
		saved.SourceID = s.serverID
		saved.SourceRevision = saved.Revision
		saved.OriginUpdatedAt = now
		if input.ClearSensitive || (input.SensitivePresent && isJSONNull(sensitive)) {
			saved.SensitiveCiphertext = ""
			saved.SensitiveFormat = ""
		} else if input.SensitivePresent {
			if err := encryptSensitive(&saved, key, sensitive); err != nil {
				return err
			}
		}
		return tx.Save(&saved).Error
	})
	if err != nil {
		return ResourceView{}, fmt.Errorf("save resource: %w", err)
	}
	return resourceView(saved, key, input.SensitivePresent)
}

func (s *Store) Get(
	ctx context.Context,
	user model.User,
	key []byte,
	kind, externalID string,
	includeSensitive bool,
) (ResourceView, error) {
	if err := validateResourceKey(kind, externalID); err != nil {
		return ResourceView{}, err
	}
	var resource model.Resource
	if err := s.db.WithContext(ctx).Where(
		"user_id = ? AND kind = ? AND external_id = ? AND deleted = ?",
		user.ID,
		kind,
		externalID,
		false,
	).First(&resource).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ResourceView{}, ErrNotFound
		}
		return ResourceView{}, fmt.Errorf("load resource: %w", err)
	}
	if includeSensitive && resource.SensitiveCiphertext != "" && len(key) == 0 {
		return ResourceView{}, secure.ErrKeyRequired
	}
	return resourceView(resource, key, includeSensitive)
}

func (s *Store) List(
	ctx context.Context,
	user model.User,
	key []byte,
	kind string,
	includeDeleted, includeSensitive bool,
) ([]ResourceView, error) {
	query := s.db.WithContext(ctx).Where("user_id = ?", user.ID)
	if kind != "" {
		if err := validateKind(kind); err != nil {
			return nil, err
		}
		query = query.Where("kind = ?", kind)
	}
	if !includeDeleted {
		query = query.Where("deleted = ?", false)
	}
	var resources []model.Resource
	if err := query.Order("kind ASC").Order("external_id ASC").Find(&resources).Error; err != nil {
		return nil, fmt.Errorf("list resources: %w", err)
	}
	views := make([]ResourceView, 0, len(resources))
	for _, resource := range resources {
		if includeSensitive && resource.SensitiveCiphertext != "" && len(key) == 0 {
			return nil, secure.ErrKeyRequired
		}
		view, err := resourceView(resource, key, includeSensitive)
		if err != nil {
			return nil, err
		}
		views = append(views, view)
	}
	return views, nil
}

func (s *Store) Delete(
	ctx context.Context,
	user model.User,
	kind, externalID string,
	expectedRevision *int64,
) error {
	if err := validateResourceKey(kind, externalID); err != nil {
		return err
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var resource model.Resource
		if err := tx.Where(
			"user_id = ? AND kind = ? AND external_id = ? AND deleted = ?",
			user.ID,
			kind,
			externalID,
			false,
		).First(&resource).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrNotFound
			}
			return err
		}
		if expectedRevision != nil && resource.Revision != *expectedRevision {
			return ErrRevisionConflict
		}
		now := time.Now().UTC()
		resource.Deleted = true
		resource.DeletedAt = &now
		resource.PlainJSON = "{}"
		resource.SensitiveCiphertext = ""
		resource.SensitiveFormat = ""
		resource.Revision++
		resource.SourceID = s.serverID
		resource.SourceRevision = resource.Revision
		resource.OriginUpdatedAt = now
		if err := tx.Save(&resource).Error; err != nil {
			return fmt.Errorf("delete resource: %w", err)
		}
		return nil
	})
}

func (s *Store) Export(
	ctx context.Context,
	user model.User,
	key []byte,
	includeDeleted, includeSensitive bool,
) (ExportBundle, error) {
	resources, err := s.List(ctx, user, key, "", includeDeleted, includeSensitive)
	if err != nil {
		return ExportBundle{}, err
	}
	return ExportBundle{
		SchemaVersion: 1,
		SourceID:      s.serverID,
		ExportedAt:    time.Now().UTC(),
		Resources:     resources,
	}, nil
}

func (s *Store) Merge(
	ctx context.Context,
	user model.User,
	key []byte,
	request MergeRequest,
) (MergeReport, error) {
	if request.SchemaVersion != 1 {
		return MergeReport{}, fmt.Errorf("%w: unsupported migration schema version", ErrInvalidResource)
	}
	if request.SourceID == "" || len(request.SourceID) > 64 {
		return MergeReport{}, fmt.Errorf("%w: source_id is required", ErrInvalidResource)
	}
	if len(request.Resources) > maxMigrationResources {
		return MergeReport{}, fmt.Errorf("%w: migration contains more than %d resources", ErrInvalidResource, maxMigrationResources)
	}
	policy := request.ConflictPolicy
	if policy == "" {
		policy = PreserveDestination
	}
	if policy != PreserveDestination && policy != SourceWins && policy != NewerWins {
		return MergeReport{}, fmt.Errorf("%w: unsupported conflict_policy", ErrInvalidResource)
	}

	report := MergeReport{Results: make([]MergeItemResult, 0, len(request.Resources))}
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		for _, incoming := range request.Resources {
			result, err := s.mergeOne(tx, user, key, request.SourceID, policy, request.PropagateDeletes, incoming)
			if err != nil {
				return err
			}
			report.Results = append(report.Results, result)
			switch result.Status {
			case "created":
				report.Created++
			case "updated":
				report.Updated++
			case "deleted":
				report.Deleted++
			case "conflict":
				report.Conflicts++
			default:
				report.Skipped++
			}
		}
		return nil
	})
	if err != nil {
		return MergeReport{}, fmt.Errorf("merge migration: %w", err)
	}
	return report, nil
}

func (s *Store) mergeOne(
	tx *gorm.DB,
	user model.User,
	key []byte,
	sourceID string,
	policy ConflictPolicy,
	propagateDeletes bool,
	incoming ResourceView,
) (MergeItemResult, error) {
	result := MergeItemResult{Kind: incoming.Kind, ID: incoming.ID}
	if err := validateResourceKey(incoming.Kind, incoming.ID); err != nil {
		return result, err
	}
	plain, err := canonicalJSON(incoming.Data, incoming.Deleted)
	if err != nil {
		return result, fmt.Errorf("%w: %s/%s data: %v", ErrInvalidResource, incoming.Kind, incoming.ID, err)
	}
	var sensitive []byte
	sensitivePresent := len(incoming.Sensitive) > 0
	if sensitivePresent {
		if len(key) == 0 {
			return result, secure.ErrKeyRequired
		}
		sensitive, err = canonicalJSON(incoming.Sensitive, true)
		if err != nil {
			return result, fmt.Errorf("%w: %s/%s sensitive: %v", ErrInvalidResource, incoming.Kind, incoming.ID, err)
		}
	}
	if incoming.Deleted && !propagateDeletes {
		result.Status = "skipped"
		result.Reason = "source deletion propagation is disabled"
		return result, nil
	}

	var existing model.Resource
	queryErr := tx.Where(
		"user_id = ? AND kind = ? AND external_id = ?",
		user.ID,
		incoming.Kind,
		incoming.ID,
	).First(&existing).Error
	now := time.Now().UTC()
	originUpdatedAt := incoming.SourceUpdatedAt.UTC()
	if originUpdatedAt.IsZero() {
		originUpdatedAt = now
	}
	sourceRevision := incoming.SourceRevision
	if sourceRevision <= 0 {
		sourceRevision = incoming.Revision
	}
	if sourceRevision <= 0 {
		sourceRevision = 1
	}

	if errors.Is(queryErr, gorm.ErrRecordNotFound) {
		if incoming.Deleted {
			result.Status = "skipped"
			result.Reason = "destination has no matching resource to delete"
			return result, nil
		}
		id, idErr := identity.UUID()
		if idErr != nil {
			return result, idErr
		}
		created := model.Resource{
			ID:              id,
			UserID:          user.ID,
			Kind:            incoming.Kind,
			ExternalID:      incoming.ID,
			PlainJSON:       string(plain),
			Revision:        1,
			SourceID:        sourceID,
			SourceRevision:  sourceRevision,
			OriginUpdatedAt: originUpdatedAt,
		}
		if sensitivePresent && !isJSONNull(sensitive) {
			if err := encryptSensitive(&created, key, sensitive); err != nil {
				return result, err
			}
		}
		if err := tx.Create(&created).Error; err != nil {
			return result, err
		}
		result.Status = "created"
		return result, nil
	}
	if queryErr != nil {
		return result, queryErr
	}
	identical, err := sameResource(existing, key, plain, sensitive, sensitivePresent, incoming.Deleted)
	if err != nil {
		return result, err
	}
	if identical {
		result.Status = "skipped"
		result.Reason = "content is unchanged"
		return result, nil
	}
	enrichSensitive := !incoming.Deleted &&
		bytes.Equal([]byte(existing.PlainJSON), plain) &&
		sensitivePresent &&
		!isJSONNull(sensitive) &&
		existing.SensitiveCiphertext == ""
	if existing.SourceID == sourceID && existing.SourceRevision >= sourceRevision && !enrichSensitive {
		result.Status = "skipped"
		result.Reason = "source revision was already applied"
		return result, nil
	}

	shouldApply := enrichSensitive || (incoming.Deleted && propagateDeletes)
	switch policy {
	case SourceWins:
		shouldApply = true
	case NewerWins:
		shouldApply = shouldApply || originUpdatedAt.After(existing.OriginUpdatedAt)
	case PreserveDestination:
		// A later sensitive export may enrich an earlier plaintext-only import
		// without changing destination-owned plaintext data. Explicit deletion
		// propagation is likewise treated as an opt-in decision.
	}
	if !shouldApply {
		result.Status = "conflict"
		result.Reason = "destination resource was preserved"
		return result, nil
	}

	existing.PlainJSON = string(plain)
	existing.Revision++
	existing.SourceID = sourceID
	existing.SourceRevision = sourceRevision
	existing.OriginUpdatedAt = originUpdatedAt
	if incoming.Deleted {
		existing.Deleted = true
		existing.DeletedAt = &now
		existing.PlainJSON = "{}"
		existing.SensitiveCiphertext = ""
		existing.SensitiveFormat = ""
	} else {
		existing.Deleted = false
		existing.DeletedAt = nil
		if sensitivePresent {
			if isJSONNull(sensitive) {
				existing.SensitiveCiphertext = ""
				existing.SensitiveFormat = ""
			} else if err := encryptSensitive(&existing, key, sensitive); err != nil {
				return result, err
			}
		}
	}
	if err := tx.Save(&existing).Error; err != nil {
		return result, err
	}
	if incoming.Deleted {
		result.Status = "deleted"
	} else {
		result.Status = "updated"
	}
	return result, nil
}

func resourceView(resource model.Resource, key []byte, includeSensitive bool) (ResourceView, error) {
	view := ResourceView{
		ID:              resource.ExternalID,
		Kind:            resource.Kind,
		Data:            json.RawMessage(resource.PlainJSON),
		HasSensitive:    resource.SensitiveCiphertext != "",
		Revision:        resource.Revision,
		SourceID:        resource.SourceID,
		SourceRevision:  resource.SourceRevision,
		SourceUpdatedAt: resource.OriginUpdatedAt,
		Deleted:         resource.Deleted,
		CreatedAt:       resource.CreatedAt,
		UpdatedAt:       resource.UpdatedAt,
	}
	if includeSensitive && resource.SensitiveCiphertext != "" && len(key) > 0 {
		cleartext, err := decryptSensitive(resource, key)
		if err != nil {
			return ResourceView{}, err
		}
		view.Sensitive = json.RawMessage(cleartext)
	}
	return view, nil
}

func sameResource(
	existing model.Resource,
	key, plain, sensitive []byte,
	sensitivePresent, deleted bool,
) (bool, error) {
	if existing.Deleted != deleted {
		return false, nil
	}
	if !deleted && !bytes.Equal([]byte(existing.PlainJSON), plain) {
		return false, nil
	}
	if !sensitivePresent {
		return true, nil
	}
	if isJSONNull(sensitive) {
		return existing.SensitiveCiphertext == "", nil
	}
	if existing.SensitiveCiphertext == "" {
		return false, nil
	}
	cleartext, err := decryptSensitive(existing, key)
	if err != nil {
		return false, err
	}
	return bytes.Equal(cleartext, sensitive), nil
}

func encryptSensitive(resource *model.Resource, key, cleartext []byte) error {
	ciphertext, err := secure.Encrypt(
		key,
		cleartext,
		secure.AssociatedData(resource.UserID, resource.Kind, resource.ExternalID),
	)
	if err != nil {
		return err
	}
	resource.SensitiveCiphertext = ciphertext
	resource.SensitiveFormat = secure.CiphertextFormat
	return nil
}

func decryptSensitive(resource model.Resource, key []byte) ([]byte, error) {
	if resource.SensitiveFormat != secure.CiphertextFormat {
		return nil, fmt.Errorf("unsupported sensitive data format %q", resource.SensitiveFormat)
	}
	return secure.Decrypt(
		key,
		resource.SensitiveCiphertext,
		secure.AssociatedData(resource.UserID, resource.Kind, resource.ExternalID),
	)
}

func canonicalJSON(raw json.RawMessage, allowEmpty bool) ([]byte, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 {
		if allowEmpty {
			return []byte("null"), nil
		}
		return nil, errors.New("value is required")
	}
	if len(trimmed) > maxResourceDataBytes {
		return nil, fmt.Errorf("value exceeds %d bytes", maxResourceDataBytes)
	}
	decoder := json.NewDecoder(bytes.NewReader(trimmed))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		return nil, err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err == nil {
		return nil, errors.New("value contains trailing JSON")
	} else if !errors.Is(err, io.EOF) {
		return nil, err
	}
	canonical, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	return canonical, nil
}

func validateResourceKey(kind, externalID string) error {
	if err := validateKind(kind); err != nil {
		return err
	}
	if externalID == "" || len(externalID) > 191 || !resourcePartPattern.MatchString(externalID) {
		return fmt.Errorf("%w: invalid resource id", ErrInvalidResource)
	}
	return nil
}

func validateKind(kind string) error {
	if kind == "" || len(kind) > 64 || !resourcePartPattern.MatchString(kind) {
		return fmt.Errorf("%w: invalid resource kind", ErrInvalidResource)
	}
	return nil
}

func isJSONNull(value []byte) bool {
	return string(bytes.TrimSpace(value)) == "null"
}

func ensureServerID(ctx context.Context, db *gorm.DB) (string, error) {
	var setting model.Setting
	err := db.WithContext(ctx).Where("key = ?", serverIDSetting).First(&setting).Error
	if err == nil {
		if strings.TrimSpace(setting.Value) == "" {
			return "", errors.New("stored server id is empty")
		}
		return setting.Value, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return "", fmt.Errorf("load server id: %w", err)
	}
	serverID, err := identity.UUID()
	if err != nil {
		return "", err
	}
	setting = model.Setting{Key: serverIDSetting, Value: serverID}
	if err := db.WithContext(ctx).Create(&setting).Error; err != nil {
		// A concurrent initializer may have inserted the setting first.
		if loadErr := db.WithContext(ctx).Where("key = ?", serverIDSetting).First(&setting).Error; loadErr == nil {
			return setting.Value, nil
		}
		return "", fmt.Errorf("save server id: %w", err)
	}
	return serverID, nil
}
