package store

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
	"time"

	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/identity"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/secure"
)

const (
	serverIDSetting          = "server_id"
	cursorSigningKeySetting  = "cursor_signing_key_v1"
	maxResourceDataBytes     = 4 << 20
	DefaultPageLimit         = 100
	MaximumPageLimit         = 100
	maxMigrationResources    = MaximumPageLimit
	MaximumJSONResponseBytes = 12 << 20
	maximumPageCursorBytes   = 1024
	responseEnvelopeReserve  = 2048
)

var (
	ErrNotFound         = errors.New("resource not found")
	ErrRevisionConflict = errors.New("resource revision conflict")
	ErrInvalidResource  = errors.New("invalid resource")
	ErrInvalidPage      = errors.New("invalid resource page")
	ErrResponseTooLarge = errors.New("resource response exceeds the documented limit")
	resourcePartPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]*$`)
	internalIDPattern   = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
)

type Store struct {
	db               *gorm.DB
	serverID         string
	cursorSigningKey []byte
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

type ResourcePage struct {
	Resources  []ResourceView `json:"resources"`
	NextCursor string         `json:"next_cursor,omitempty"`
	snapshot   time.Time
}

type ExportBundle struct {
	SchemaVersion int            `json:"schema_version"`
	SourceID      string         `json:"source_id"`
	ExportedAt    time.Time      `json:"exported_at"`
	Resources     []ResourceView `json:"resources"`
	NextCursor    string         `json:"next_cursor,omitempty"`
}

type pageCursor struct {
	Kind              string `json:"kind"`
	ExternalID        string `json:"external_id"`
	InternalID        string `json:"internal_id"`
	SnapshotUnixNanos int64  `json:"snapshot_unix_nanos"`
	FilterKind        string `json:"filter_kind,omitempty"`
	IncludeDeleted    bool   `json:"include_deleted"`
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
	NextCursor       string         `json:"next_cursor,omitempty"`
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
	cursorSigningKey, err := ensureCursorSigningKey(ctx, db)
	if err != nil {
		return nil, err
	}
	return &Store{
		db:               db,
		serverID:         serverID,
		cursorSigningKey: cursorSigningKey,
	}, nil
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
	buildNewResource := func(now time.Time) error {
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
			CreatedAt:       now,
			UpdatedAt:       now,
		}
		if input.SensitivePresent && !isJSONNull(sensitive) {
			return encryptSensitive(&saved, key, sensitive)
		}
		return nil
	}
	if input.ExpectedRevision != nil && *input.ExpectedRevision == 0 {
		now, err := database.CurrentTime(ctx, s.db)
		if err != nil {
			return ResourceView{}, fmt.Errorf("read resource creation time: %w", err)
		}
		if err := buildNewResource(now); err != nil {
			return ResourceView{}, fmt.Errorf("save resource: %w", err)
		}
		if err := s.db.WithContext(ctx).Create(&saved).Error; err != nil {
			if errors.Is(err, gorm.ErrDuplicatedKey) {
				return ResourceView{}, fmt.Errorf("save resource: %w", ErrRevisionConflict)
			}
			return ResourceView{}, fmt.Errorf("save resource: %w", err)
		}
		return resourceView(saved, key, input.SensitivePresent)
	}
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var existing model.Resource
		queryErr := tx.Where(
			"user_id = ? AND kind = ? AND external_id = ?",
			user.ID,
			kind,
			externalID,
		).First(&existing).Error
		now, timeErr := database.CurrentTime(ctx, tx)
		if timeErr != nil {
			return timeErr
		}
		if errors.Is(queryErr, gorm.ErrRecordNotFound) {
			if input.ExpectedRevision != nil {
				return ErrRevisionConflict
			}
			if err := buildNewResource(now); err != nil {
				return err
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
	limit int,
	cursor string,
) (ResourcePage, error) {
	if limit < 1 || limit > MaximumPageLimit {
		return ResourcePage{}, fmt.Errorf("%w: limit must be between 1 and %d", ErrInvalidPage, MaximumPageLimit)
	}
	var pagePosition pageCursor
	var snapshot time.Time
	var err error
	if cursor == "" {
		snapshot, err = database.CurrentTime(ctx, s.db)
	} else {
		pagePosition, snapshot, err = s.decodePageCursor(cursor)
	}
	if err != nil {
		return ResourcePage{}, fmt.Errorf("prepare resource page snapshot: %w", err)
	}
	query := s.db.WithContext(ctx).Where("user_id = ?", user.ID)
	if cursor != "" && (pagePosition.FilterKind != kind || pagePosition.IncludeDeleted != includeDeleted) {
		return ResourcePage{}, fmt.Errorf("%w: cursor does not match resource filters", ErrInvalidPage)
	}
	if kind != "" {
		if err := validateKind(kind); err != nil {
			return ResourcePage{}, err
		}
		query = query.Where("kind = ?", kind)
	}
	if !includeDeleted {
		query = query.Where("deleted = ?", false)
	}
	query = query.Where("created_at <= ?", snapshot)
	if cursor != "" {
		query = query.Where(
			"(kind > ?) OR (kind = ? AND external_id > ?) OR (kind = ? AND external_id = ? AND id > ?)",
			pagePosition.Kind,
			pagePosition.Kind,
			pagePosition.ExternalID,
			pagePosition.Kind,
			pagePosition.ExternalID,
			pagePosition.InternalID,
		)
	}
	rows, err := query.Model(&model.Resource{}).
		Order("kind ASC").
		Order("external_id ASC").
		Order("id ASC").
		Limit(limit + 1).
		Rows()
	if err != nil {
		return ResourcePage{}, fmt.Errorf("list resources: %w", err)
	}
	defer rows.Close()

	views := make([]ResourceView, 0, limit)
	encodedBytes := 0
	hasMore := false
	var last model.Resource
	for rows.Next() {
		if len(views) == limit {
			hasMore = true
			break
		}
		var resource model.Resource
		if err := s.db.ScanRows(rows, &resource); err != nil {
			return ResourcePage{}, fmt.Errorf("scan resource page: %w", err)
		}
		if includeSensitive && resource.SensitiveCiphertext != "" && len(key) == 0 {
			return ResourcePage{}, secure.ErrKeyRequired
		}
		view, err := resourceView(resource, key, includeSensitive)
		if err != nil {
			return ResourcePage{}, err
		}
		encoded, err := json.Marshal(view)
		if err != nil {
			return ResourcePage{}, fmt.Errorf("encode resource page item: %w", err)
		}
		separatorBytes := 0
		if len(views) > 0 {
			separatorBytes = 1
		}
		if encodedBytes+separatorBytes+len(encoded) > MaximumJSONResponseBytes-responseEnvelopeReserve {
			if len(views) == 0 {
				return ResourcePage{}, ErrResponseTooLarge
			}
			hasMore = true
			break
		}
		views = append(views, view)
		encodedBytes += separatorBytes + len(encoded)
		last = resource
	}
	if err := rows.Err(); err != nil {
		return ResourcePage{}, fmt.Errorf("iterate resource page: %w", err)
	}
	page := ResourcePage{Resources: views, snapshot: snapshot}
	if hasMore {
		page.NextCursor, err = s.encodePageCursor(last, snapshot, kind, includeDeleted)
		if err != nil {
			return ResourcePage{}, err
		}
	}
	return page, nil
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
		now, err := database.CurrentTime(ctx, tx)
		if err != nil {
			return err
		}
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
	limit int,
	cursor string,
) (ExportBundle, error) {
	page, err := s.List(ctx, user, key, "", includeDeleted, includeSensitive, limit, cursor)
	if err != nil {
		return ExportBundle{}, err
	}
	return ExportBundle{
		SchemaVersion: 1,
		SourceID:      s.serverID,
		ExportedAt:    page.snapshot,
		Resources:     page.Resources,
		NextCursor:    page.NextCursor,
	}, nil
}

func (s *Store) decodePageCursor(encoded string) (pageCursor, time.Time, error) {
	if len(encoded) > maximumPageCursorBytes {
		return pageCursor{}, time.Time{}, fmt.Errorf("%w: cursor is too large", ErrInvalidPage)
	}
	parts := strings.Split(encoded, ".")
	if len(parts) != 2 {
		return pageCursor{}, time.Time{}, fmt.Errorf("%w: cursor is malformed", ErrInvalidPage)
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return pageCursor{}, time.Time{}, fmt.Errorf("%w: cursor is malformed", ErrInvalidPage)
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return pageCursor{}, time.Time{}, fmt.Errorf("%w: cursor is malformed", ErrInvalidPage)
	}
	mac := hmac.New(sha256.New, s.cursorSigningKey)
	_, _ = mac.Write(raw)
	if !hmac.Equal(signature, mac.Sum(nil)) {
		return pageCursor{}, time.Time{}, fmt.Errorf("%w: cursor signature is invalid", ErrInvalidPage)
	}
	var cursor pageCursor
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&cursor); err != nil {
		return pageCursor{}, time.Time{}, fmt.Errorf("%w: cursor is malformed", ErrInvalidPage)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return pageCursor{}, time.Time{}, fmt.Errorf("%w: cursor is malformed", ErrInvalidPage)
	}
	if err := validateResourceKey(cursor.Kind, cursor.ExternalID); err != nil ||
		!internalIDPattern.MatchString(cursor.InternalID) || cursor.SnapshotUnixNanos <= 0 {
		return pageCursor{}, time.Time{}, fmt.Errorf("%w: cursor fields are invalid", ErrInvalidPage)
	}
	snapshot := time.Unix(0, cursor.SnapshotUnixNanos).UTC()
	return cursor, snapshot, nil
}

func (s *Store) encodePageCursor(
	resource model.Resource,
	snapshot time.Time,
	filterKind string,
	includeDeleted bool,
) (string, error) {
	encoded, err := json.Marshal(pageCursor{
		Kind:              resource.Kind,
		ExternalID:        resource.ExternalID,
		InternalID:        resource.ID,
		SnapshotUnixNanos: snapshot.UnixNano(),
		FilterKind:        filterKind,
		IncludeDeleted:    includeDeleted,
	})
	if err != nil {
		return "", fmt.Errorf("encode resource page cursor: %w", err)
	}
	mac := hmac.New(sha256.New, s.cursorSigningKey)
	_, _ = mac.Write(encoded)
	return base64.RawURLEncoding.EncodeToString(encoded) + "." +
		base64.RawURLEncoding.EncodeToString(mac.Sum(nil)), nil
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
	now, err := database.CurrentTime(tx.Statement.Context, tx)
	if err != nil {
		return result, err
	}
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
			CreatedAt:       now,
			UpdatedAt:       now,
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

func ensureCursorSigningKey(ctx context.Context, db *gorm.DB) ([]byte, error) {
	var setting model.Setting
	err := db.WithContext(ctx).Where("key = ?", cursorSigningKeySetting).First(&setting).Error
	if err == nil {
		if strings.TrimSpace(setting.Value) == "" {
			return nil, errors.New("stored cursor signing key is empty")
		}
		return []byte(setting.Value), nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("load cursor signing key: %w", err)
	}
	key, err := identity.Secret(32)
	if err != nil {
		return nil, err
	}
	setting = model.Setting{Key: cursorSigningKeySetting, Value: key}
	if err := db.WithContext(ctx).Create(&setting).Error; err != nil {
		// A concurrent initializer may have inserted the setting first.
		if loadErr := db.WithContext(ctx).
			Where("key = ?", cursorSigningKeySetting).
			First(&setting).Error; loadErr == nil && strings.TrimSpace(setting.Value) != "" {
			return []byte(setting.Value), nil
		}
		return nil, fmt.Errorf("save cursor signing key: %w", err)
	}
	return []byte(key), nil
}
