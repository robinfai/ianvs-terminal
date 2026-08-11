package database_test

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gorm.io/driver/mysql"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/auth"
	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/identity"
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
		&authTokenV1{},
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
	if !equalVersions(versions, []uint{1, database.CurrentSchemaVersion}) {
		t.Fatalf("schema migration versions = %v, want [1 %d]", versions, database.CurrentSchemaVersion)
	}
}

func TestOpenMigratesVersionOneAuthenticationOperations(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "version-one.db"))
	legacy, err := openUnversionedDatabase(cfg)
	if err != nil {
		t.Fatalf("open version-one database: %v", err)
	}
	if err := legacy.AutoMigrate(
		&model.User{},
		&authTokenV1{},
		&model.Resource{},
		&model.Setting{},
		&schemaMigrationV1{},
	); err != nil {
		t.Fatalf("create version-one schema: %v", err)
	}
	if err := legacy.Create(&schemaMigrationV1{Version: 1, AppliedAt: time.Now().UTC()}).Error; err != nil {
		t.Fatalf("record version-one schema: %v", err)
	}
	legacyUser := model.User{
		ID:       "10000000-0000-4000-8000-000000000001",
		Username: "legacy-token-user",
	}
	if err := legacy.Create(&legacyUser).Error; err != nil {
		t.Fatalf("seed version-one user: %v", err)
	}
	rawToken, err := identity.Secret(32)
	if err != nil {
		t.Fatalf("generate version-one token: %v", err)
	}
	digest := sha256.Sum256([]byte(rawToken))
	tokenHash := hex.EncodeToString(digest[:])
	tokenExpiry := time.Now().UTC().Add(time.Hour).Truncate(time.Millisecond)
	legacyToken := authTokenV1{
		ID:        "20000000-0000-4000-8000-000000000002",
		UserID:    legacyUser.ID,
		TokenHash: tokenHash,
		ExpiresAt: tokenExpiry,
		CreatedAt: time.Now().UTC().Truncate(time.Millisecond),
	}
	if err := legacy.Create(&legacyToken).Error; err != nil {
		t.Fatalf("seed version-one token: %v", err)
	}
	closeGormDB(t, legacy)

	migrated, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("migrate version-one database: %v", err)
	}
	defer closeGormDB(t, migrated)
	if !migrated.Migrator().HasTable(&model.AuthOperation{}) {
		t.Fatal("version-two migration omitted auth_operations")
	}
	if !migrated.Migrator().HasColumn(&model.AuthToken{}, "OperationHash") {
		t.Fatal("version-two migration omitted auth_tokens.operation_hash")
	}
	var migratedToken model.AuthToken
	if err := migrated.Where("id = ?", legacyToken.ID).First(&migratedToken).Error; err != nil {
		t.Fatalf("load migrated version-one token: %v", err)
	}
	if migratedToken.TokenHash != tokenHash {
		t.Fatal("version-one token digest changed during migration")
	}
	if migratedToken.OperationHash != nil {
		t.Fatalf("version-one operation hash = %v, want nil", migratedToken.OperationHash)
	}
	if !migratedToken.ExpiresAt.Equal(tokenExpiry) {
		t.Fatalf("version-one expiry = %s, want %s", migratedToken.ExpiresAt, tokenExpiry)
	}
	authService := auth.New(migrated, time.Hour)
	authenticated, err := authService.AuthenticateToken(context.Background(), rawToken)
	if err != nil {
		t.Fatalf("authenticate migrated version-one token: %v", err)
	}
	if authenticated.ID != legacyUser.ID {
		t.Fatalf("authenticated migrated user = %q, want %q", authenticated.ID, legacyUser.ID)
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
	if !equalVersions(versions, []uint{1, database.CurrentSchemaVersion}) {
		t.Fatalf("concurrent schema migration versions = %v, want [1 %d]", versions, database.CurrentSchemaVersion)
	}
}

func TestSQLiteRuntimeBusyTimeoutSurvivesPoolTurnover(t *testing.T) {
	cfg := config.Config{
		Mode:           config.ModeRemote,
		DatabaseDriver: "sqlite",
		DatabaseDSN:    filepath.Join(t.TempDir(), "pool-turnover.db"),
		TokenTTL:       time.Hour,
	}
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("database.Open() error = %v", err)
	}
	defer closeGormDB(t, db)
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("database pool: %v", err)
	}
	sqlDB.SetMaxIdleConns(0)
	sqlDB.SetConnMaxLifetime(time.Nanosecond)
	for attempt := 0; attempt < 3; attempt++ {
		var busyMilliseconds int
		if err := db.Raw("PRAGMA busy_timeout").Scan(&busyMilliseconds).Error; err != nil {
			t.Fatalf("read busy_timeout after pool turnover %d: %v", attempt+1, err)
		}
		if busyMilliseconds != 5000 {
			t.Fatalf("busy_timeout after pool turnover %d = %d, want 5000", attempt+1, busyMilliseconds)
		}
	}
}

func TestSQLiteRuntimeBusyWaitsAcrossDatabaseHandles(t *testing.T) {
	cfg := config.Config{
		Mode:           config.ModeRemote,
		DatabaseDriver: "sqlite",
		DatabaseDSN:    filepath.Join(t.TempDir(), "two-handles.db"),
		TokenTTL:       time.Hour,
	}
	first, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("open first database handle: %v", err)
	}
	defer closeGormDB(t, first)
	second, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("open second database handle: %v", err)
	}
	defer closeGormDB(t, second)
	if err := first.Create(&model.Setting{Key: "runtime-busy-test", Value: "initial"}).Error; err != nil {
		t.Fatalf("seed runtime busy row: %v", err)
	}

	locked := make(chan struct{})
	release := make(chan struct{})
	firstResult := make(chan error, 1)
	go func() {
		firstResult <- first.Transaction(func(tx *gorm.DB) error {
			if err := tx.Model(&model.Setting{}).
				Where("key = ?", "runtime-busy-test").
				Update("value", "first").Error; err != nil {
				return err
			}
			close(locked)
			<-release
			return nil
		})
	}()
	select {
	case <-locked:
	case <-time.After(5 * time.Second):
		t.Fatal("timed out acquiring first SQLite write transaction")
	}

	secondResult := make(chan error, 1)
	go func() {
		secondResult <- second.Model(&model.Setting{}).
			Where("key = ?", "runtime-busy-test").
			Update("value", "second").Error
	}()
	select {
	case err := <-secondResult:
		t.Fatalf("second SQLite writer did not wait for the first transaction: %v", err)
	case <-time.After(100 * time.Millisecond):
	}
	close(release)
	if err := <-firstResult; err != nil {
		t.Fatalf("first SQLite writer: %v", err)
	}
	select {
	case err := <-secondResult:
		if err != nil {
			t.Fatalf("second SQLite writer after release: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for second SQLite writer")
	}
}

type authTokenV1 struct {
	ID        string    `gorm:"primaryKey;size:36"`
	UserID    string    `gorm:"index;size:36;not null"`
	TokenHash string    `gorm:"uniqueIndex;size:64;not null"`
	ExpiresAt time.Time `gorm:"index;not null"`
	CreatedAt time.Time `gorm:"not null"`
}

func (authTokenV1) TableName() string { return "auth_tokens" }

type schemaMigrationV1 struct {
	Version   uint      `gorm:"primaryKey;autoIncrement:false"`
	AppliedAt time.Time `gorm:"not null"`
}

func (schemaMigrationV1) TableName() string { return "schema_migrations" }

func equalVersions(actual, expected []uint) bool {
	if len(actual) != len(expected) {
		return false
	}
	for index := range actual {
		if actual[index] != expected[index] {
			return false
		}
	}
	return true
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
