package auth

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/identity"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/secure"
)

const (
	LocalUsername                   = "__local__"
	minimumPasswordSize             = 12
	maximumPasswordSize             = 72
	maximumConcurrentPasswordHashes = 2
	localUserReloadAttempts         = 10
	OperationIDEncodedSize          = 43
	maximumActiveSessionsPerUser    = 8
	maximumPreparedOperationTTL     = 5 * time.Minute
	authOperationKindLogin          = "login"
	authOperationKindRegister       = "register"
	authOperationStatePrepared      = "prepared"
	authOperationStateIssued        = "issued"
	authOperationStateCanceled      = "canceled"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUsernameTaken      = errors.New("username is already registered")
	ErrInvalidUsername    = errors.New("username must be 3-64 lowercase letters, numbers, dots, underscores, or hyphens")
	ErrInvalidPassword    = fmt.Errorf("password must contain %d-%d UTF-8 bytes", minimumPasswordSize, maximumPasswordSize)
	ErrPasswordHashBusy   = errors.New("password hashing capacity is busy")
	ErrInvalidOperationID = errors.New("operation_id must be 32 random bytes encoded as unpadded base64url")
	ErrOperationNotFound  = errors.New("authentication operation was not found")
	ErrOperationKind      = errors.New("authentication operation kind does not match the completion endpoint")
	ErrOperationCanceled  = errors.New("authentication operation was canceled")
	ErrOperationReused    = errors.New("authentication operation was already used")
	ErrSessionCapacity    = fmt.Errorf("a user may have at most %d active authentication operations", maximumActiveSessionsPerUser)
	usernamePattern       = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{2,63}$`)
	passwordHashAdmission = newPasswordHashAdmission(maximumConcurrentPasswordHashes)
)

type passwordHashAdmissionGate struct {
	slots chan struct{}
}

func newPasswordHashAdmission(capacity int) *passwordHashAdmissionGate {
	return &passwordHashAdmissionGate{slots: make(chan struct{}, capacity)}
}

func (a *passwordHashAdmissionGate) run(operation func() error) error {
	select {
	case a.slots <- struct{}{}:
		defer func() { <-a.slots }()
		return operation()
	default:
		return ErrPasswordHashBusy
	}
}

type Service struct {
	db          *gorm.DB
	tokenTTL    time.Duration
	beforeIssue func()
}

type Session struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	User      UserView  `json:"user"`
}

type PreparedOperation struct {
	OperationID string    `json:"operation_id"`
	ExpiresAt   time.Time `json:"expires_at"`
	Kind        string    `json:"kind"`
}

type UserView struct {
	ID                   string `json:"id"`
	Username             string `json:"username"`
	KeyConfigured        bool   `json:"key_configured"`
	KeyContractVersion   int    `json:"key_contract_version"`
	KeyRotationSupported bool   `json:"key_rotation_supported"`
}

func New(db *gorm.DB, tokenTTL time.Duration) *Service {
	return &Service{db: db, tokenTTL: tokenTTL}
}

func View(user model.User) UserView {
	return UserView{
		ID:                   user.ID,
		Username:             user.Username,
		KeyConfigured:        user.KeyVerifier != "",
		KeyContractVersion:   secure.KeyContractVersion,
		KeyRotationSupported: false,
	}
}

func (s *Service) EnsureLocalUser(ctx context.Context) (model.User, error) {
	var user model.User
	err := s.db.WithContext(ctx).Where("username = ?", LocalUsername).First(&user).Error
	if err == nil {
		return user, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return model.User{}, fmt.Errorf("load local user: %w", err)
	}
	id, err := identity.UUID()
	if err != nil {
		return model.User{}, err
	}
	user = model.User{ID: id, Username: LocalUsername}
	if err := s.db.WithContext(ctx).Create(&user).Error; err != nil {
		if !errors.Is(err, gorm.ErrDuplicatedKey) {
			return model.User{}, fmt.Errorf("create local user: %w", err)
		}
		user = model.User{}
		var loadErr error
		for attempt := 0; attempt < localUserReloadAttempts; attempt++ {
			loadErr = s.db.WithContext(ctx).Where("username = ?", LocalUsername).First(&user).Error
			if loadErr == nil {
				return user, nil
			}
			if ctx.Err() != nil {
				return model.User{}, ctx.Err()
			}
			time.Sleep(time.Duration(attempt+1) * time.Millisecond)
		}
		return model.User{}, errors.Join(
			fmt.Errorf("create local user: %w", err),
			fmt.Errorf("reload concurrently created local user: %w", loadErr),
		)
	}
	return user, nil
}

func (s *Service) SetupLocalKey(ctx context.Context, secret string) (model.User, bool, error) {
	user, err := s.EnsureLocalUser(ctx)
	if err != nil {
		return model.User{}, false, err
	}
	if user.KeyVerifier != "" {
		if _, err := secure.VerifyUserKey(user, secret); err != nil {
			return model.User{}, false, err
		}
		return user, false, nil
	}
	configured := user
	if _, err := secure.ConfigureUserKey(&configured, secret); err != nil {
		return model.User{}, false, err
	}
	result := s.db.WithContext(ctx).
		Model(&model.User{}).
		Where("id = ? AND key_verifier = ?", user.ID, "").
		Updates(map[string]any{
			"key_derivation": configured.KeyDerivation,
			"key_salt":       configured.KeySalt,
			"key_verifier":   configured.KeyVerifier,
		})
	if result.Error != nil {
		return model.User{}, false, fmt.Errorf("save local encryption key verifier: %w", result.Error)
	}
	if result.RowsAffected == 1 {
		return configured, true, nil
	}

	var winner model.User
	if err := s.db.WithContext(ctx).Where("id = ?", user.ID).First(&winner).Error; err != nil {
		return model.User{}, false, fmt.Errorf("reload local encryption key verifier: %w", err)
	}
	if _, err := secure.VerifyUserKey(winner, secret); err != nil {
		return model.User{}, false, err
	}
	return winner, false, nil
}

func (s *Service) BeginRegister(
	ctx context.Context,
	username, password, encryptionKey string,
) (PreparedOperation, error) {
	username = normalizeUsername(username)
	if !usernamePattern.MatchString(username) || username == LocalUsername {
		return PreparedOperation{}, ErrInvalidUsername
	}
	if len(password) < minimumPasswordSize || len(password) > maximumPasswordSize {
		return PreparedOperation{}, ErrInvalidPassword
	}
	if err := secure.ValidateUserKeyForConfiguration(encryptionKey); err != nil {
		return PreparedOperation{}, err
	}
	var passwordHash []byte
	err := passwordHashAdmission.run(func() error {
		var hashErr error
		passwordHash, hashErr = bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		return hashErr
	})
	if err != nil {
		return PreparedOperation{}, fmt.Errorf("hash password: %w", err)
	}
	id, err := identity.UUID()
	if err != nil {
		return PreparedOperation{}, err
	}
	user := model.User{
		ID:           id,
		Username:     username,
		PasswordHash: string(passwordHash),
	}
	if _, err := secure.ConfigureUserKey(&user, encryptionKey); err != nil {
		return PreparedOperation{}, err
	}
	operationID, err := identity.Secret(32)
	if err != nil {
		return PreparedOperation{}, err
	}

	var prepared PreparedOperation
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		now, err := database.CurrentTime(ctx, tx)
		if err != nil {
			return err
		}
		if err := cleanupExpiredAuthState(tx, now); err != nil {
			return err
		}
		var count int64
		if err := tx.Model(&model.User{}).Where("username = ?", username).Count(&count).Error; err != nil {
			return err
		}
		if count != 0 {
			return ErrUsernameTaken
		}
		if err := tx.Create(&user).Error; err != nil {
			if errors.Is(err, gorm.ErrDuplicatedKey) {
				return ErrUsernameTaken
			}
			return fmt.Errorf("create user: %w", err)
		}
		expiresAt := now.Add(s.preparedOperationTTL())
		if err := tx.Create(&model.AuthOperation{
			OperationHash: hashOperationID(operationID),
			Kind:          authOperationKindRegister,
			State:         authOperationStatePrepared,
			UserID:        user.ID,
			ExpiresAt:     expiresAt,
		}).Error; err != nil {
			return fmt.Errorf("create prepared registration operation: %w", err)
		}
		prepared = PreparedOperation{
			OperationID: operationID,
			ExpiresAt:   expiresAt,
			Kind:        authOperationKindRegister,
		}
		return nil
	})
	if err != nil {
		return PreparedOperation{}, err
	}
	return prepared, nil
}

func (s *Service) BeginLogin(ctx context.Context, username, password string) (PreparedOperation, error) {
	username = normalizeUsername(username)
	if len(password) < minimumPasswordSize || len(password) > maximumPasswordSize {
		return PreparedOperation{}, ErrInvalidCredentials
	}
	var user model.User
	if err := s.db.WithContext(ctx).Where("username = ?", username).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return PreparedOperation{}, ErrInvalidCredentials
		}
		return PreparedOperation{}, fmt.Errorf("load login user: %w", err)
	}
	if user.PasswordHash == "" {
		return PreparedOperation{}, ErrInvalidCredentials
	}
	var passwordMatches bool
	if err := passwordHashAdmission.run(func() error {
		passwordMatches = bcrypt.CompareHashAndPassword(
			[]byte(user.PasswordHash),
			[]byte(password),
		) == nil
		return nil
	}); err != nil {
		return PreparedOperation{}, err
	}
	if !passwordMatches {
		return PreparedOperation{}, ErrInvalidCredentials
	}
	operationID, err := identity.Secret(32)
	if err != nil {
		return PreparedOperation{}, err
	}

	var prepared PreparedOperation
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := lockUserAuthOperations(tx, user.ID); err != nil {
			return err
		}
		now, err := database.CurrentTime(ctx, tx)
		if err != nil {
			return err
		}
		if err := cleanupExpiredAuthState(tx, now); err != nil {
			return err
		}
		if err := ensureUserSessionCapacity(tx, user.ID, now); err != nil {
			return err
		}
		expiresAt := now.Add(s.preparedOperationTTL())
		if err := tx.Create(&model.AuthOperation{
			OperationHash: hashOperationID(operationID),
			Kind:          authOperationKindLogin,
			State:         authOperationStatePrepared,
			UserID:        user.ID,
			ExpiresAt:     expiresAt,
		}).Error; err != nil {
			return fmt.Errorf("create prepared login operation: %w", err)
		}
		prepared = PreparedOperation{
			OperationID: operationID,
			ExpiresAt:   expiresAt,
			Kind:        authOperationKindLogin,
		}
		return nil
	})
	if err != nil {
		return PreparedOperation{}, err
	}
	return prepared, nil
}

func (s *Service) CompleteLogin(ctx context.Context, operationID string) (Session, error) {
	return s.completeOperation(ctx, operationID, authOperationKindLogin)
}

func (s *Service) CompleteRegister(ctx context.Context, operationID string) (Session, error) {
	return s.completeOperation(ctx, operationID, authOperationKindRegister)
}

func (s *Service) completeOperation(ctx context.Context, operationID, expectedKind string) (Session, error) {
	if err := ValidateOperationID(operationID); err != nil {
		return Session{}, err
	}
	if s.beforeIssue != nil {
		s.beforeIssue()
	}
	var session Session
	var completionErr error
	operationHash := hashOperationID(operationID)
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		now, err := database.CurrentTime(ctx, tx)
		if err != nil {
			return err
		}
		var operation model.AuthOperation
		if err := loadAuthOperationForUpdate(tx, operationHash, &operation); err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrOperationNotFound
			}
			return fmt.Errorf("load prepared authentication operation: %w", err)
		}
		if !operation.ExpiresAt.After(now) {
			if err := tx.Where("operation_hash = ?", operationHash).Delete(&model.AuthToken{}).Error; err != nil {
				return fmt.Errorf("delete expired authentication operation token: %w", err)
			}
			if err := tx.Delete(&operation).Error; err != nil {
				return fmt.Errorf("delete expired authentication operation: %w", err)
			}
			completionErr = ErrOperationNotFound
			return nil
		}
		if operation.Kind != expectedKind {
			return ErrOperationKind
		}
		switch operation.State {
		case authOperationStateCanceled:
			return ErrOperationCanceled
		case authOperationStateIssued:
			return ErrOperationReused
		case authOperationStatePrepared:
		default:
			return fmt.Errorf("unsupported authentication operation state %q", operation.State)
		}
		var user model.User
		if err := tx.Where("id = ?", operation.UserID).First(&user).Error; err != nil {
			return fmt.Errorf("load authentication operation user: %w", err)
		}
		operation.State = authOperationStateIssued
		operation.ExpiresAt = now.Add(s.tokenTTL)
		if err := tx.Save(&operation).Error; err != nil {
			return fmt.Errorf("mark authentication operation issued: %w", err)
		}
		created, err := s.issueReservedToken(tx, user, operation)
		if err != nil {
			return err
		}
		session = created
		return nil
	})
	if err != nil {
		return Session{}, err
	}
	if completionErr != nil {
		return Session{}, completionErr
	}
	return session, nil
}

// CancelOperation idempotently cancels an existing server-prepared operation.
// Unknown capabilities never create rows, so anonymous callers cannot consume
// authentication-operation capacity with random valid-looking values.
func (s *Service) CancelOperation(ctx context.Context, operationID string) error {
	if err := ValidateOperationID(operationID); err != nil {
		return err
	}
	operationHash := hashOperationID(operationID)
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		now, err := database.CurrentTime(ctx, tx)
		if err != nil {
			return err
		}
		var operation model.AuthOperation
		if err := loadAuthOperationForUpdate(tx, operationHash, &operation); err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return nil
			}
			return fmt.Errorf("load authentication operation for cancellation: %w", err)
		}
		if err := tx.Where("operation_hash = ?", operationHash).Delete(&model.AuthToken{}).Error; err != nil {
			return fmt.Errorf("revoke authentication operation token: %w", err)
		}
		if !operation.ExpiresAt.After(now) {
			if err := tx.Delete(&operation).Error; err != nil {
				return fmt.Errorf("delete expired authentication operation: %w", err)
			}
			return nil
		}
		if operation.State != authOperationStateCanceled {
			if err := tx.Model(&operation).Update("state", authOperationStateCanceled).Error; err != nil {
				return fmt.Errorf("cancel authentication operation: %w", err)
			}
		}
		return nil
	})
}

func (s *Service) AuthenticateToken(ctx context.Context, rawToken string) (model.User, error) {
	if strings.TrimSpace(rawToken) == "" {
		return model.User{}, ErrInvalidCredentials
	}
	now, err := database.CurrentTime(ctx, s.db)
	if err != nil {
		return model.User{}, fmt.Errorf("read authentication clock: %w", err)
	}
	var token model.AuthToken
	if err := s.db.WithContext(ctx).Where(
		"token_hash = ? AND expires_at > ?",
		hashToken(rawToken),
		now,
	).First(&token).Error; err != nil {
		return model.User{}, ErrInvalidCredentials
	}
	var user model.User
	if err := s.db.WithContext(ctx).Where("id = ?", token.UserID).First(&user).Error; err != nil {
		return model.User{}, ErrInvalidCredentials
	}
	return user, nil
}

func (s *Service) Logout(ctx context.Context, rawToken string) error {
	if strings.TrimSpace(rawToken) == "" {
		return nil
	}
	tokenHash := hashToken(rawToken)
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// The first read discovers the owning user and optional operation. The
		// user lock then serializes this capacity release with BeginLogin's
		// capacity reservation across API instances.
		var token model.AuthToken
		if err := tx.Where("token_hash = ?", tokenHash).First(&token).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return nil
			}
			return fmt.Errorf("load auth token for logout: %w", err)
		}
		if err := lockUserAuthOperations(tx, token.UserID); err != nil {
			return err
		}

		// Cancellation and completion lock the operation before touching its
		// token. Preserve that order here so concurrent cancel/logout cannot
		// deadlock.
		var operation *model.AuthOperation
		var linked model.AuthOperation
		if err := loadAuthOperationForUpdate(tx, token.OperationHash, &linked); err != nil {
			if !errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("load authentication operation for logout: %w", err)
			}
		} else {
			operation = &linked
		}

		if err := tx.Where("token_hash = ?", tokenHash).Delete(&model.AuthToken{}).Error; err != nil {
			return fmt.Errorf("delete auth token: %w", err)
		}
		if operation != nil && operation.State != authOperationStateCanceled {
			if err := tx.Model(operation).Update("state", authOperationStateCanceled).Error; err != nil {
				return fmt.Errorf("release logged-out authentication operation: %w", err)
			}
		}
		return nil
	})
}

func (s *Service) VerifyKey(user model.User, secret string) ([]byte, error) {
	return secure.VerifyUserKey(user, secret)
}

func (s *Service) preparedOperationTTL() time.Duration {
	if s.tokenTTL < maximumPreparedOperationTTL {
		return s.tokenTTL
	}
	return maximumPreparedOperationTTL
}

func lockUserAuthOperations(db *gorm.DB, userID string) error {
	result := db.Model(&model.User{}).
		Where("id = ?", userID).
		UpdateColumn("id", gorm.Expr("id"))
	if result.Error != nil {
		return fmt.Errorf("lock user authentication operations: %w", result.Error)
	}
	return nil
}

func ensureUserSessionCapacity(db *gorm.DB, userID string, now time.Time) error {
	var operationCount int64
	if err := db.Model(&model.AuthOperation{}).
		Where(
			"user_id = ? AND expires_at > ? AND state IN ?",
			userID,
			now,
			[]string{authOperationStatePrepared, authOperationStateIssued},
		).
		Count(&operationCount).Error; err != nil {
		return fmt.Errorf("count active authentication operations: %w", err)
	}
	if operationCount >= maximumActiveSessionsPerUser {
		return ErrSessionCapacity
	}
	return nil
}

func (s *Service) issueReservedToken(
	db *gorm.DB,
	user model.User,
	operation model.AuthOperation,
) (Session, error) {
	rawToken, err := identity.Secret(32)
	if err != nil {
		return Session{}, err
	}
	tokenID, err := identity.UUID()
	if err != nil {
		return Session{}, err
	}
	expiresAt := operation.ExpiresAt
	token := model.AuthToken{
		ID:            tokenID,
		UserID:        user.ID,
		TokenHash:     hashToken(rawToken),
		OperationHash: operation.OperationHash,
		ExpiresAt:     expiresAt,
	}
	if err := db.Create(&token).Error; err != nil {
		return Session{}, fmt.Errorf("create auth token: %w", err)
	}
	return Session{
		Token:     rawToken,
		ExpiresAt: expiresAt,
		User:      View(user),
	}, nil
}

func loadAuthOperationForUpdate(db *gorm.DB, operationHash string, operation *model.AuthOperation) error {
	return db.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("operation_hash = ?", operationHash).
		First(operation).Error
}

func ValidateOperationID(operationID string) error {
	if len(operationID) != OperationIDEncodedSize {
		return ErrInvalidOperationID
	}
	decoded, err := base64.RawURLEncoding.DecodeString(operationID)
	if err != nil || len(decoded) != 32 || base64.RawURLEncoding.EncodeToString(decoded) != operationID {
		return ErrInvalidOperationID
	}
	return nil
}

func cleanupExpiredAuthState(db *gorm.DB, now time.Time) error {
	if err := db.Where("expires_at <= ?", now).Delete(&model.AuthToken{}).Error; err != nil {
		return fmt.Errorf("delete expired authentication tokens: %w", err)
	}
	if err := db.Where("expires_at <= ?", now).Delete(&model.AuthOperation{}).Error; err != nil {
		return fmt.Errorf("delete expired authentication operations: %w", err)
	}
	return nil
}

func normalizeUsername(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func hashToken(token string) string {
	digest := sha256.Sum256([]byte(token))
	return hex.EncodeToString(digest[:])
}

func hashOperationID(operationID string) string {
	digest := sha256.Sum256([]byte(operationID))
	return hex.EncodeToString(digest[:])
}
