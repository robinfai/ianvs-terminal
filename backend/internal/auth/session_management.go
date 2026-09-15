package auth

import (
	"context"
	"gorm.io/gorm"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/model"
	"strings"
	"time"
	"unicode"
)

type SessionView struct {
	DeviceName string    `json:"device_name"`
	ID         string    `json:"id"`
	CreatedAt  time.Time `json:"created_at"`
	ExpiresAt  time.Time `json:"expires_at"`
	Current    bool      `json:"current"`
}

func (s *Service) ListSessions(ctx context.Context, userID, rawToken string) ([]SessionView, error) {
	now, err := database.CurrentTime(ctx, s.db)
	if err != nil {
		return nil, err
	}
	var tokens []model.AuthToken
	if err := s.db.WithContext(ctx).Where("user_id = ? AND expires_at > ?", userID, now).
		Order("created_at DESC, id ASC").Find(&tokens).Error; err != nil {
		return nil, err
	}
	views := make([]SessionView, 0, len(tokens))
	for _, t := range tokens {
		var metadata model.Setting
		name := ""
		result := s.db.WithContext(ctx).Where("key = ?", sessionMetadataKey(t.OperationHash)).Limit(1).Find(&metadata)
		if result.Error != nil {
			return nil, result.Error
		}
		if result.RowsAffected > 0 {
			name = metadata.Value
		}
		views = append(views, SessionView{DeviceName: name, ID: t.ID, CreatedAt: t.CreatedAt, ExpiresAt: t.ExpiresAt, Current: t.TokenHash == hashToken(rawToken)})
	}
	return views, nil
}

// RevokeSession only accepts an opaque token row ID owned by this user.
func (s *Service) RevokeSession(ctx context.Context, userID, id string) error {
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := lockUserAuthOperations(tx, userID); err != nil {
			return err
		}
		var tokens []model.AuthToken
		if err := tx.Where("user_id = ? AND id = ?", userID, id).Find(&tokens).Error; err != nil {
			return err
		}
		for _, t := range tokens {
			if err := revokeOperation(tx, t.OperationHash); err != nil {
				return err
			}
		}
		return nil
	})
}

func revokeOperation(tx *gorm.DB, operationHash string) error {
	var operation model.AuthOperation
	if err := loadAuthOperationForUpdate(tx, operationHash, &operation); err != nil {
		return err
	}
	if err := tx.Where("operation_hash = ?", operationHash).Delete(&model.AuthToken{}).Error; err != nil {
		return err
	}
	if err := tx.Where("key = ?", sessionMetadataKey(operationHash)).Delete(&model.Setting{}).Error; err != nil {
		return err
	}
	return tx.Model(&operation).Update("state", authOperationStateCanceled).Error
}

// Device labels are display-only, never used to authenticate or identify ownership.
// Server-private settings keep this additive metadata compatible with schema v1.
type deviceNameKey struct{}

func WithDeviceName(ctx context.Context, name string) context.Context {
	name = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, name)
	chars := []rune(strings.TrimSpace(name))
	if len(chars) > 128 {
		chars = chars[:128]
	}
	return context.WithValue(ctx, deviceNameKey{}, string(chars))
}
func sessionMetadataKey(operationHash string) string { return "auth.session.device/" + operationHash }
