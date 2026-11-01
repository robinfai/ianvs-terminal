package auth

import (
	"context"
	"errors"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/identity"
	"ianvs-terminal/backend/internal/model"
)

var ErrAppleLinkConflict = errors.New("Apple account or existing account is already linked")
var ErrAppleRegistrationDisabled = errors.New("sign in with an existing account to link Apple; new account registration is disabled")

const appleChallengePrefix = "auth.apple.challenge/"

// Metadata keys keep existing databases and account/resource IDs intact.
// Neither Apple's email nor its client-supplied user identifier is an identity.
func (s *Service) CreateAppleChallenge(ctx context.Context) (string, error) {
	nonce, err := identity.Secret(32)
	if err != nil {
		return "", err
	}
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		now, err := database.CurrentTime(ctx, tx)
		if err != nil {
			return err
		}
		if err := tx.Where("`key` LIKE ? AND created_at < ?", appleChallengePrefix+"%", now.Add(-5*time.Minute)).Delete(&model.Setting{}).Error; err != nil {
			return err
		}
		var count int64
		if err := tx.Model(&model.Setting{}).Where("`key` LIKE ?", appleChallengePrefix+"%").Count(&count).Error; err != nil {
			return err
		}
		if count >= 1024 {
			return ErrSessionCapacity
		}
		return tx.Create(&model.Setting{Key: appleChallengePrefix + hashToken(nonce), Value: "pending", CreatedAt: now, UpdatedAt: now}).Error
	})
	return nonce, err
}

// BeginAppleLogin binds only after proof of both identities. Binding never
// moves resources, replaces another binding, or merges accounts by email.
func (s *Service) BeginAppleLogin(ctx context.Context, subject, nonce, username, password string, allowRegistration bool) (PreparedOperation, error) {
	if subject == "" || ValidateOperationID(nonce) != nil {
		return PreparedOperation{}, ErrAppleIdentity
	}
	var historical model.User
	if username != "" || password != "" {
		if len(password) < minimumPasswordSize || len(password) > maximumPasswordSize {
			return PreparedOperation{}, ErrInvalidCredentials
		}
		if err := s.db.WithContext(ctx).Where("username = ?", normalizeUsername(username)).First(&historical).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return PreparedOperation{}, ErrInvalidCredentials
			}
			return PreparedOperation{}, err
		}
		matches := false
		if err := passwordHashAdmission.run(func() error {
			matches = historical.PasswordHash != "" && bcrypt.CompareHashAndPassword([]byte(historical.PasswordHash), []byte(password)) == nil
			return nil
		}); err != nil {
			return PreparedOperation{}, err
		}
		if !matches {
			return PreparedOperation{}, ErrInvalidCredentials
		}
	}
	var prepared PreparedOperation
	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		now, err := database.CurrentTime(ctx, tx)
		if err != nil {
			return err
		}
		consumed := tx.Where("`key` = ? AND created_at >= ?", appleChallengePrefix+hashToken(nonce), now.Add(-5*time.Minute)).Delete(&model.Setting{})
		if consumed.Error != nil {
			return consumed.Error
		}
		if consumed.RowsAffected != 1 {
			return ErrAppleIdentity
		}
		subjectKey := "auth.apple.subject/" + hashToken(subject)
		var mapping model.Setting
		err = tx.Where("`key` = ?", subjectKey).First(&mapping).Error
		var user model.User
		if err == nil {
			if historical.ID != "" && mapping.Value != historical.ID {
				return ErrAppleLinkConflict
			}
			if err := tx.Where("id = ?", mapping.Value).First(&user).Error; err != nil {
				return err
			}
		} else if errors.Is(err, gorm.ErrRecordNotFound) {
			user = historical
			if user.ID == "" {
				if !allowRegistration {
					return ErrAppleRegistrationDisabled
				}
				id, err := identity.UUID()
				if err != nil {
					return err
				}
				user = model.User{ID: id, Username: "apple_" + hashToken(subject)[:32]}
				if err := tx.Create(&user).Error; err != nil {
					return err
				}
			}
			// Unique keys enforce one Apple identity per account and one account per Apple identity.
			for _, m := range []model.Setting{{Key: "auth.apple.user/" + user.ID, Value: subjectKey}, {Key: subjectKey, Value: user.ID}} {
				if err := tx.Create(&m).Error; err != nil {
					if errors.Is(err, gorm.ErrDuplicatedKey) {
						return ErrAppleLinkConflict
					}
					return err
				}
			}
		} else {
			return err
		}
		scoped := &Service{db: tx, tokenTTL: s.tokenTTL}
		prepared, err = scoped.beginLoginForUser(ctx, user, false)
		return err
	})
	return prepared, err
}
