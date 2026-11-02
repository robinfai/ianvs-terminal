package auth

import (
	"context"
	"errors"
	"gorm.io/gorm"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/model"
	"time"
)

// LinkedProviders exposes provider names only, never subjects or tokens.
func (s *Service) LinkedProviders(ctx context.Context, userID string) ([]string, error) {
	providers := []string{}
	for _, provider := range []string{"apple", "google"} {
		var count int64
		if err := s.db.WithContext(ctx).Model(&model.Setting{}).Where("`key` = ?", "auth."+provider+".user/"+userID).Count(&count).Error; err != nil {
			return nil, err
		}
		if count > 0 {
			providers = append(providers, provider)
		}
	}
	return providers, nil
}

// LinkOAuthIdentity binds a verified provider proof to the authenticated account.
// It cannot transfer an identity, merge accounts, or replace an existing binding.
func (s *Service) LinkOAuthIdentity(ctx context.Context, userID, provider, subject, nonce string) error {
	if (provider != "apple" && provider != "google") || subject == "" || ValidateOperationID(nonce) != nil {
		return ErrAppleIdentity
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var user model.User
		if err := tx.Where("id = ?", userID).First(&user).Error; err != nil {
			return err
		}
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
		subjectKey := "auth." + provider + ".subject/" + hashToken(subject)
		userKey := "auth." + provider + ".user/" + userID
		var mapping model.Setting
		err = tx.Where("`key` = ?", subjectKey).First(&mapping).Error
		if err == nil {
			if mapping.Value == userID {
				return nil
			}
			return ErrAppleLinkConflict
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		for _, item := range []model.Setting{{Key: userKey, Value: subjectKey}, {Key: subjectKey, Value: userID}} {
			if err := tx.Create(&item).Error; err != nil {
				if errors.Is(err, gorm.ErrDuplicatedKey) {
					return ErrAppleLinkConflict
				}
				return err
			}
		}
		return nil
	})
}
