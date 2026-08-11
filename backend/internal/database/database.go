package database

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"gorm.io/driver/mysql"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/model"
)

func Open(cfg config.Config) (*gorm.DB, error) {
	var dialector gorm.Dialector
	switch cfg.DatabaseDriver {
	case "sqlite":
		if err := prepareSQLiteParent(cfg.DatabaseDSN); err != nil {
			return nil, err
		}
		dialector = sqlite.Open(cfg.DatabaseDSN)
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
	db, err := gorm.Open(dialector, &gorm.Config{Logger: ormLogger})
	if err != nil {
		return nil, fmt.Errorf("open %s database: %w", cfg.DatabaseDriver, err)
	}
	if err := migrate(db); err != nil {
		return nil, err
	}
	if sqlDB, err := db.DB(); err == nil {
		configurePool(sqlDB, cfg.DatabaseDriver)
	}
	return db, nil
}

func migrate(db *gorm.DB) error {
	if err := db.AutoMigrate(
		&model.User{},
		&model.AuthToken{},
		&model.Resource{},
		&model.Setting{},
	); err != nil {
		return fmt.Errorf("migrate database: %w", err)
	}
	return nil
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
