package database

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/mattn/go-sqlite3"
	"gorm.io/driver/mysql"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
)

// CurrentSchemaVersion is the latest durable database schema understood by
// this backend binary.
const CurrentSchemaVersion uint = 2

const (
	mysqlMigrationLockTimeout = 15 * time.Second
	sqliteBusyTimeout         = 5 * time.Second
	sqliteMigrationAttempts   = 4
)

type schemaMigration struct {
	Version   uint      `gorm:"primaryKey;autoIncrement:false"`
	AppliedAt time.Time `gorm:"not null"`
}

func (schemaMigration) TableName() string { return "schema_migrations" }

var schemaMigrations = []struct {
	version uint
	apply   func(*gorm.DB) error
}{
	{
		version: 1,
		apply: func(db *gorm.DB) error {
			return db.AutoMigrate(
				&model.User{},
				&authTokenV1{},
				&model.Resource{},
				&model.Setting{},
			)
		},
	},
	{
		version: 2,
		apply: func(db *gorm.DB) error {
			return db.AutoMigrate(
				&model.AuthToken{},
				&model.AuthOperation{},
			)
		},
	},
}

// authTokenV1 freezes the version-1 table shape so rebuilding an unversioned
// database still applies each durable migration in order.
type authTokenV1 struct {
	ID        string    `gorm:"primaryKey;size:36"`
	UserID    string    `gorm:"index;size:36;not null"`
	TokenHash string    `gorm:"uniqueIndex;size:64;not null"`
	ExpiresAt time.Time `gorm:"index;not null"`
	CreatedAt time.Time `gorm:"not null"`
}

func (authTokenV1) TableName() string { return "auth_tokens" }

func Open(cfg config.Config) (*gorm.DB, error) {
	var dialector gorm.Dialector
	switch cfg.DatabaseDriver {
	case "sqlite":
		if err := prepareSQLiteParent(cfg.DatabaseDSN); err != nil {
			return nil, err
		}
		runtimeDSN, err := sqliteRuntimeDSN(cfg.DatabaseDSN)
		if err != nil {
			return nil, err
		}
		dialector = sqlite.Open(runtimeDSN)
	case "mysql":
		dialector = mysql.Open(cfg.DatabaseDSN)
	default:
		return nil, fmt.Errorf("unsupported database driver %q", cfg.DatabaseDriver)
	}

	ormLogger := logger.New(
		log.New(os.Stderr, "", log.LstdFlags),
		logger.Config{
			SlowThreshold:             time.Second,
			LogLevel:                  logger.Warn,
			IgnoreRecordNotFoundError: true,
			ParameterizedQueries:      true,
			Colorful:                  false,
		},
	)
	db, err := gorm.Open(dialector, &gorm.Config{
		Logger:         ormLogger,
		TranslateError: true,
		NowFunc: func() time.Time {
			return time.Now().UTC()
		},
	})
	if err != nil {
		return nil, fmt.Errorf("open %s database: %w", cfg.DatabaseDriver, err)
	}
	if err := migrate(db, cfg.DatabaseDriver); err != nil {
		if sqlDB, poolErr := db.DB(); poolErr == nil {
			_ = sqlDB.Close()
		}
		return nil, err
	}
	if sqlDB, err := db.DB(); err == nil {
		configurePool(sqlDB, cfg.DatabaseDriver)
	}
	return db, nil
}

func sqliteRuntimeDSN(dsn string) (string, error) {
	parts := strings.SplitN(dsn, "?", 2)
	query := url.Values{}
	if len(parts) == 2 {
		var err error
		query, err = url.ParseQuery(parts[1])
		if err != nil {
			return "", fmt.Errorf("parse SQLite DSN options: %w", err)
		}
	}
	query.Set("_busy_timeout", strconv.FormatInt(sqliteBusyTimeout.Milliseconds(), 10))
	query.Set("_txlock", "immediate")
	return parts[0] + "?" + query.Encode(), nil
}

// CurrentTime returns one UTC instant owned by the database rather than the
// application process. Cross-instance cursor snapshots and resource creation
// timestamps use this clock so host clock skew cannot hide or admit rows.
func CurrentTime(ctx context.Context, db *gorm.DB) (time.Time, error) {
	var unixMicros int64
	var query string
	switch db.Dialector.Name() {
	case "sqlite":
		query = "SELECT CAST((julianday('now') - 2440587.5) * 86400000000 AS INTEGER)"
	case "mysql":
		query = "SELECT CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(6)) * 1000000 AS SIGNED)"
	default:
		return time.Time{}, fmt.Errorf("unsupported database clock dialect %q", db.Dialector.Name())
	}
	if err := db.WithContext(ctx).Raw(query).Scan(&unixMicros).Error; err != nil {
		return time.Time{}, fmt.Errorf("read database UTC clock: %w", err)
	}
	if unixMicros <= 0 {
		return time.Time{}, errors.New("database UTC clock returned an invalid timestamp")
	}
	return time.UnixMicro(unixMicros).UTC(), nil
}

func migrate(db *gorm.DB, driver string) error {
	switch driver {
	case "mysql":
		return migrateMySQL(db)
	case "sqlite":
		return migrateSQLite(db)
	default:
		return fmt.Errorf("unsupported migration driver %q", driver)
	}
}

func migrateMySQL(db *gorm.DB) error {
	return db.Connection(func(connection *gorm.DB) (migrationErr error) {
		var databaseName string
		if err := connection.Raw("SELECT DATABASE()").Scan(&databaseName).Error; err != nil {
			return fmt.Errorf("read MySQL migration database name: %w", err)
		}
		if databaseName == "" {
			return errors.New("MySQL migration requires a selected database")
		}
		digest := sha256.Sum256([]byte(databaseName))
		lockName := fmt.Sprintf("ianvs-schema-%x", digest[:16])

		lockContext, cancelLock := context.WithTimeout(
			context.Background(),
			mysqlMigrationLockTimeout+time.Second,
		)
		defer cancelLock()
		var acquired sql.NullInt64
		if err := connection.WithContext(lockContext).Raw(
			"SELECT GET_LOCK(?, ?)",
			lockName,
			int(mysqlMigrationLockTimeout/time.Second),
		).Scan(&acquired).Error; err != nil {
			return fmt.Errorf("acquire MySQL schema migration lock: %w", err)
		}
		if !acquired.Valid || acquired.Int64 != 1 {
			return fmt.Errorf(
				"acquire MySQL schema migration lock: timed out after %s",
				mysqlMigrationLockTimeout,
			)
		}

		defer func() {
			releaseContext, cancelRelease := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancelRelease()
			var released sql.NullInt64
			releaseErr := connection.WithContext(releaseContext).Raw(
				"SELECT RELEASE_LOCK(?)",
				lockName,
			).Scan(&released).Error
			if releaseErr == nil && (!released.Valid || released.Int64 != 1) {
				releaseErr = errors.New("MySQL reported that the schema migration lock was not held")
			}
			if releaseErr != nil {
				migrationErr = errors.Join(
					migrationErr,
					fmt.Errorf("release MySQL schema migration lock: %w", releaseErr),
				)
			}
		}()

		// MySQL DDL implicitly commits. The named lock serializes instances, and
		// each idempotent migration writes its ledger row only after DDL succeeds.
		return migrateOnce(connection.WithContext(context.Background()))
	})
}

func migrateSQLite(db *gorm.DB) error {
	return db.Connection(func(connection *gorm.DB) error {
		busyMilliseconds := sqliteBusyTimeout / time.Millisecond
		if err := connection.Exec(
			fmt.Sprintf("PRAGMA busy_timeout = %d", busyMilliseconds),
		).Error; err != nil {
			return fmt.Errorf("configure SQLite migration busy timeout: %w", err)
		}

		var lastBusyError error
		for attempt := 0; attempt < sqliteMigrationAttempts; attempt++ {
			err := migrateSQLiteOnce(connection)
			if err == nil {
				return nil
			}
			if !isSQLiteBusy(err) {
				return err
			}
			lastBusyError = err

			complete, verifyErr := currentSchemaIsApplied(
				connection.Session(&gorm.Session{NewDB: true}),
			)
			if verifyErr == nil && complete {
				return nil
			}
			if verifyErr != nil && !isSQLiteBusy(verifyErr) {
				return errors.Join(err, fmt.Errorf("re-read SQLite schema version: %w", verifyErr))
			}
			if attempt+1 < sqliteMigrationAttempts {
				time.Sleep(time.Duration(attempt+1) * 50 * time.Millisecond)
			}
		}
		return fmt.Errorf(
			"SQLite schema migration remained busy after %d attempts: %w",
			sqliteMigrationAttempts,
			lastBusyError,
		)
	})
}

func migrateSQLiteOnce(connection *gorm.DB) (migrationErr error) {
	if err := connection.Exec("BEGIN IMMEDIATE").Error; err != nil {
		return fmt.Errorf("acquire SQLite schema migration write lock: %w", err)
	}
	defer func() {
		if migrationErr != nil {
			rollbackErr := connection.Exec("ROLLBACK").Error
			if rollbackErr != nil {
				migrationErr = errors.Join(
					migrationErr,
					fmt.Errorf("rollback SQLite schema migration: %w", rollbackErr),
				)
			}
		}
	}()

	migrationDB := connection.Session(&gorm.Session{
		NewDB:                  true,
		SkipDefaultTransaction: true,
	})
	if err := migrateOnce(migrationDB); err != nil {
		return err
	}
	if err := connection.Exec("COMMIT").Error; err != nil {
		return fmt.Errorf("commit SQLite schema migration: %w", err)
	}
	return nil
}

func migrateOnce(db *gorm.DB) error {
	if err := db.AutoMigrate(&schemaMigration{}); err != nil {
		return fmt.Errorf("create schema migration ledger: %w", err)
	}
	latestVersion, err := readAndValidateSchemaVersion(db)
	if err != nil {
		return err
	}
	for _, migration := range schemaMigrations {
		if migration.version <= latestVersion {
			continue
		}
		apply := func(tx *gorm.DB) error {
			if err := migration.apply(tx); err != nil {
				return err
			}
			return tx.Create(&schemaMigration{
				Version:   migration.version,
				AppliedAt: time.Now().UTC(),
			}).Error
		}
		// SQLite's caller holds one outer transaction. MySQL's caller holds its
		// advisory lock because MySQL DDL cannot be transactionally rolled back.
		if err := apply(db); err != nil {
			return fmt.Errorf("apply database schema migration %d: %w", migration.version, err)
		}
		latestVersion = migration.version
	}
	finalVersion, err := readAndValidateSchemaVersion(db)
	if err != nil {
		return err
	}
	if finalVersion != CurrentSchemaVersion {
		return fmt.Errorf(
			"database schema migration incomplete: reached version %d, expected %d",
			finalVersion,
			CurrentSchemaVersion,
		)
	}
	return nil
}

func readAndValidateSchemaVersion(db *gorm.DB) (uint, error) {
	var latest schemaMigration
	err := db.Order("version DESC").First(&latest).Error
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return 0, fmt.Errorf("read schema migration ledger: %w", err)
	}
	if latest.Version > CurrentSchemaVersion {
		return 0, fmt.Errorf(
			"database schema version %d is newer than supported version %d",
			latest.Version,
			CurrentSchemaVersion,
		)
	}
	return latest.Version, nil
}

func currentSchemaIsApplied(db *gorm.DB) (bool, error) {
	if !db.Migrator().HasTable(&schemaMigration{}) {
		return false, nil
	}
	version, err := readAndValidateSchemaVersion(db)
	if err != nil {
		return false, err
	}
	return version == CurrentSchemaVersion, nil
}

func isSQLiteBusy(err error) bool {
	var sqliteError sqlite3.Error
	if !errors.As(err, &sqliteError) {
		return false
	}
	return sqliteError.Code == sqlite3.ErrBusy || sqliteError.Code == sqlite3.ErrLocked
}

func configurePool(db *sql.DB, driver string) {
	if driver == "sqlite" {
		// One writer avoids SQLITE_BUSY without issuing dialect-specific PRAGMAs.
		db.SetMaxOpenConns(1)
		db.SetMaxIdleConns(1)
	} else {
		db.SetMaxOpenConns(20)
		db.SetMaxIdleConns(10)
	}
	db.SetConnMaxLifetime(30 * time.Minute)
}

func prepareSQLiteParent(dsn string) error {
	// URI-style and in-memory DSNs have no filesystem parent to create.
	if dsn == ":memory:" || strings.HasPrefix(dsn, "file:") {
		return nil
	}
	parent := filepath.Dir(dsn)
	if parent == "." || parent == "" {
		return nil
	}
	if err := os.MkdirAll(parent, 0o700); err != nil {
		return fmt.Errorf("create sqlite database directory: %w", err)
	}
	return nil
}
