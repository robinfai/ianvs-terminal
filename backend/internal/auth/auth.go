package auth

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

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
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUsernameTaken      = errors.New("username is already registered")
	ErrInvalidUsername    = errors.New("username must be 3-64 lowercase letters, numbers, dots, underscores, or hyphens")
	ErrInvalidPassword    = fmt.Errorf("password must contain %d-%d UTF-8 bytes", minimumPasswordSize, maximumPasswordSize)
	ErrPasswordHashBusy   = errors.New("password hashing capacity is busy")
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
	db       *gorm.DB
	tokenTTL time.Duration
}

type Session struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	User      UserView  `json:"user"`
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

func (s *Service) Register(
	ctx context.Context,
	username, password, encryptionKey string,
) (Session, error) {
	username = normalizeUsername(username)
	if !usernamePattern.MatchString(username) || username == LocalUsername {
		return Session{}, ErrInvalidUsername
	}
	if len(password) < minimumPasswordSize || len(password) > maximumPasswordSize {
		return Session{}, ErrInvalidPassword
	}
	if err := secure.ValidateUserKeyForConfiguration(encryptionKey); err != nil {
		return Session{}, err
	}
	var passwordHash []byte
	err := passwordHashAdmission.run(func() error {
		var hashErr error
		passwordHash, hashErr = bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		return hashErr
	})
	if err != nil {
		return Session{}, fmt.Errorf("hash password: %w", err)
	}
	id, err := identity.UUID()
	if err != nil {
		return Session{}, err
	}
	user := model.User{
		ID:           id,
		Username:     username,
		PasswordHash: string(passwordHash),
	}
	if _, err := secure.ConfigureUserKey(&user, encryptionKey); err != nil {
		return Session{}, err
	}

	var session Session
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
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
		created, err := s.issueToken(tx, user)
		if err != nil {
			return err
		}
		session = created
		return nil
	})
	if err != nil {
		return Session{}, err
	}
	return session, nil
}

func (s *Service) Login(ctx context.Context, username, password string) (Session, error) {
	username = normalizeUsername(username)
	if len(password) < minimumPasswordSize || len(password) > maximumPasswordSize {
		return Session{}, ErrInvalidCredentials
	}
	var user model.User
	if err := s.db.WithContext(ctx).Where("username = ?", username).First(&user).Error; err != nil {
		return Session{}, ErrInvalidCredentials
	}
	if user.PasswordHash == "" {
		return Session{}, ErrInvalidCredentials
	}
	var passwordMatches bool
	if err := passwordHashAdmission.run(func() error {
		passwordMatches = bcrypt.CompareHashAndPassword(
			[]byte(user.PasswordHash),
			[]byte(password),
		) == nil
		return nil
	}); err != nil {
		return Session{}, err
	}
	if !passwordMatches {
		return Session{}, ErrInvalidCredentials
	}
	return s.issueToken(s.db.WithContext(ctx), user)
}

func (s *Service) AuthenticateToken(ctx context.Context, rawToken string) (model.User, error) {
	if strings.TrimSpace(rawToken) == "" {
		return model.User{}, ErrInvalidCredentials
	}
	var token model.AuthToken
	if err := s.db.WithContext(ctx).Where(
		"token_hash = ? AND expires_at > ?",
		hashToken(rawToken),
		time.Now().UTC(),
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
	if err := s.db.WithContext(ctx).Where("token_hash = ?", hashToken(rawToken)).Delete(&model.AuthToken{}).Error; err != nil {
		return fmt.Errorf("delete auth token: %w", err)
	}
	return nil
}

func (s *Service) VerifyKey(user model.User, secret string) ([]byte, error) {
	return secure.VerifyUserKey(user, secret)
}

func (s *Service) issueToken(db *gorm.DB, user model.User) (Session, error) {
	rawToken, err := identity.Secret(32)
	if err != nil {
		return Session{}, err
	}
	tokenID, err := identity.UUID()
	if err != nil {
		return Session{}, err
	}
	expiresAt := time.Now().UTC().Add(s.tokenTTL)
	token := model.AuthToken{
		ID:        tokenID,
		UserID:    user.ID,
		TokenHash: hashToken(rawToken),
		ExpiresAt: expiresAt,
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

func normalizeUsername(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func hashToken(token string) string {
	digest := sha256.Sum256([]byte(token))
	return hex.EncodeToString(digest[:])
}
