package database_test

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gorm.io/driver/mysql"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/model"
)

func TestOpenMigratesUnversionedSchemaAndPreservesRows(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "legacy-v0.db"))
	legacy, err := openUnversionedDatabase(cfg)
	if err != nil {
		t.Fatalf("open legacy database: %v", err)
	}
	// Version zero is the schema produced by the backend before it gained a
	// migration ledger. Reproduce that exact predecessor rather than inventing
	// an older partial model that no released binary created.
	if err := legacy.AutoMigrate(
		&model.User{},
		&model.AuthToken{},
		&model.Resource{},
		&model.Setting{},
	); err != nil {
		t.Fatalf("create unversioned predecessor schema: %v", err)
	}
	if err := legacy.Create(&model.User{
		ID:       "00000000-0000-0000-0000-000000000001",
		Username: "legacy-user",
	}).Error; err != nil {
		t.Fatalf("insert legacy row: %v", err)
	}
	closeGormDB(t, legacy)

	migrated, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("database.Open() migration error = %v", err)
	}
	t.Cleanup(func() { closeGormDB(t, migrated) })

	var user model.User
	if err := migrated.First(&user, "id = ?", "00000000-0000-0000-0000-000000000001").Error; err != nil {
		t.Fatalf("load preserved legacy user: %v", err)
	}
	if user.Username != "legacy-user" {
		t.Fatalf("preserved username = %q", user.Username)
	}
	var versions []uint
	if err := migrated.Table("schema_migrations").Order("version").Pluck("version", &versions).Error; err != nil {
		t.Fatalf("read migration ledger: %v", err)
	}
	if len(versions) != 1 || versions[0] != database.CurrentSchemaVersion {
		t.Fatalf("schema migration versions = %v, want [%d]", versions, database.CurrentSchemaVersion)
	}
}

func TestOpenRejectsSchemaFromANewerBackend(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "future.db"))
	current, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("create current database: %v", err)
	}
	if err := current.Table("schema_migrations").Create(map[string]any{
		"version":    database.CurrentSchemaVersion + 1,
		"applied_at": time.Now().UTC(),
	}).Error; err != nil {
		t.Fatalf("insert future schema version: %v", err)
	}
	closeGormDB(t, current)

	_, err = database.Open(cfg)
	if err == nil || !strings.Contains(err.Error(), "newer than supported") {
		t.Fatalf("database.Open() error = %v, want newer-schema rejection", err)
	}
}

func TestOpenSerializesConcurrentColdStart(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "concurrent.db"))
	start := make(chan struct{})
	type result struct {
		db  *gorm.DB
		err error
	}
	results := make(chan result, 2)
	for range 2 {
		go func() {
			<-start
			db, err := database.Open(cfg)
			results <- result{db: db, err: err}
		}()
	}
	close(start)

	opened := make([]*gorm.DB, 0, 2)
	for range 2 {
		result := <-results
		if result.err != nil {
			for _, db := range opened {
				closeGormDB(t, db)
			}
			t.Fatalf("concurrent database.Open() error = %v", result.err)
		}
		opened = append(opened, result.db)
	}
	for _, db := range opened {
		closeGormDB(t, db)
	}

	verified, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("reopen concurrently migrated database: %v", err)
	}
	defer closeGormDB(t, verified)
	var versions []uint
	if err := verified.Table("schema_migrations").Order("version").Pluck("version", &versions).Error; err != nil {
		t.Fatalf("read concurrent schema migration ledger: %v", err)
	}
	if len(versions) != 1 || versions[0] != database.CurrentSchemaVersion {
		t.Fatalf("concurrent schema migration versions = %v, want [%d]", versions, database.CurrentSchemaVersion)
	}
}

func testDatabaseConfiguration(t *testing.T, sqliteDSN string) config.Config {
	t.Helper()
	cfg, cleanup, err := contracttest.NewDatabaseConfiguration(
		context.Background(),
		config.ModeLocal,
		sqliteDSN,
	)
	if err != nil {
		t.Fatalf("create database contract configuration: %v", err)
	}
	t.Cleanup(func() {
		if err := cleanup(); err != nil {
			t.Errorf("clean up database contract: %v", err)
		}
	})
	return cfg
}

func openUnversionedDatabase(cfg config.Config) (*gorm.DB, error) {
	switch cfg.DatabaseDriver {
	case "sqlite":
		return gorm.Open(sqlite.Open(cfg.DatabaseDSN))
	case "mysql":
		return gorm.Open(mysql.Open(cfg.DatabaseDSN))
	default:
		return nil, fmt.Errorf("unsupported database contract driver %q", cfg.DatabaseDriver)
	}
}

func closeGormDB(t *testing.T, db *gorm.DB) {
	t.Helper()
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("obtain database pool: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close database pool: %v", err)
	}
}
