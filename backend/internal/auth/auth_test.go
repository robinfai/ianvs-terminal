package auth_test

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/model"
)

func TestEnsureLocalUserIsIdempotentUnderConcurrency(t *testing.T) {
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

	type result struct {
		user model.User
		err  error
	}
	results := make(chan result, 2)
	start := make(chan struct{})
	for range 2 {
		go func() {
			<-start
			user, err := service.EnsureLocalUser(context.Background())
			results <- result{user: user, err: err}
		}()
	}
	close(start)

	var userID string
	for range 2 {
		result := <-results
		if result.err != nil {
			t.Fatalf("EnsureLocalUser() error = %v", result.err)
		}
		if userID == "" {
			userID = result.user.ID
		} else if result.user.ID != userID {
			t.Fatalf("concurrent calls returned different users: %q and %q", userID, result.user.ID)
		}
	}

	var persisted model.User
	if err := db.Where("username = ?", auth.LocalUsername).First(&persisted).Error; err != nil {
		t.Fatalf("load local user: %v", err)
	}
	if persisted.ID != userID {
		t.Fatalf("persisted local user ID = %q, want %q", persisted.ID, userID)
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
