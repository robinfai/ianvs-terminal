package auth_test

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/secure"
)

func TestSetupLocalKeyAllowsExactlyOneConcurrentFirstKey(t *testing.T) {
	cfg, cleanup, err := contracttest.NewDatabaseConfiguration(
		context.Background(),
		config.ModeLocal,
		filepath.Join(t.TempDir(), "auth.db"),
	)
	if err != nil {
		t.Fatalf("create database contract configuration: %v", err)
	}
	t.Cleanup(func() {
		if err := cleanup(); err != nil {
			t.Errorf("clean up database contract: %v", err)
		}
	})
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("database.Open() error = %v", err)
	}
	closeDatabaseOnCleanup(t, db)
	service := auth.New(db, time.Hour)

	type setupResult struct {
		secret  string
		created bool
		err     error
	}
	results := make(chan setupResult, 2)
	start := make(chan struct{})
	secrets := []string{
		"first-concurrent-key-material",
		"second-concurrent-key-material",
	}
	for _, secret := range secrets {
		go func() {
			<-start
			_, created, err := service.SetupLocalKey(context.Background(), secret)
			results <- setupResult{secret: secret, created: created, err: err}
		}()
	}
	close(start)

	var winner setupResult
	createdCount := 0
	conflictCount := 0
	for range 2 {
		result := <-results
		switch {
		case result.err == nil && result.created:
			winner = result
			createdCount++
		case errors.Is(result.err, secure.ErrInvalidKey):
			conflictCount++
		default:
			t.Fatalf("unexpected concurrent setup result: created=%t error=%v", result.created, result.err)
		}
	}
	if createdCount != 1 || conflictCount != 1 {
		t.Fatalf("concurrent setup outcomes: created=%d conflicts=%d", createdCount, conflictCount)
	}

	var persisted model.User
	if err := db.Where("username = ?", auth.LocalUsername).First(&persisted).Error; err != nil {
		t.Fatalf("load local user: %v", err)
	}
	if _, err := secure.VerifyUserKey(persisted, winner.secret); err != nil {
		t.Fatalf("persisted verifier did not retain winning key: %T", err)
	}
}

func closeDatabaseOnCleanup(t *testing.T, db *gorm.DB) {
	t.Helper()
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("database pool error = %v", err)
	}
	t.Cleanup(func() {
		if err := sqlDB.Close(); err != nil {
			t.Errorf("close database pool: %v", err)
		}
	})
}
