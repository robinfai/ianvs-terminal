// Package contracttest contains infrastructure used only by cross-dialect
// backend contract suites.
package contracttest

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"

	"ianvs-terminal/backend/internal/config"
)

const (
	// DatabaseDriverEnvironment selects the dialect for backend contract tests.
	DatabaseDriverEnvironment = "IANVS_TEST_DATABASE_DRIVER"
	// MySQLAdminDSNEnvironment provides credentials that may create and drop
	// isolated databases. It is read only when the selected driver is mysql.
	MySQLAdminDSNEnvironment = "IANVS_TEST_MYSQL_ADMIN_DSN"
)

// NewDatabaseConfiguration returns a SQLite configuration by default and an
// isolated MySQL configuration when the contract-test environment requests it.
func NewDatabaseConfiguration(
	ctx context.Context,
	mode config.Mode,
	sqliteDSN string,
) (configuration config.Config, cleanup func() error, err error) {
	driver := strings.ToLower(strings.TrimSpace(os.Getenv(DatabaseDriverEnvironment)))
	if driver == "" || driver == "sqlite" {
		return config.Config{
			Mode:           mode,
			DatabaseDriver: "sqlite",
			DatabaseDSN:    sqliteDSN,
			TokenTTL:       time.Hour,
		}, func() error { return nil }, nil
	}
	if driver != "mysql" {
		return config.Config{}, nil, fmt.Errorf("unsupported contract database driver %q", driver)
	}
	administrativeDSN := strings.TrimSpace(os.Getenv(MySQLAdminDSNEnvironment))
	if administrativeDSN == "" {
		return config.Config{}, nil, fmt.Errorf(
			"%s is required for MySQL contract tests",
			MySQLAdminDSNEnvironment,
		)
	}
	databaseDSN, cleanup, err := ProvisionMySQL(ctx, administrativeDSN)
	if err != nil {
		return config.Config{}, nil, err
	}
	return config.Config{
		Mode:           mode,
		DatabaseDriver: "mysql",
		DatabaseDSN:    databaseDSN,
		TokenTTL:       time.Hour,
	}, cleanup, nil
}

// ProvisionMySQL creates an isolated database from an administrative DSN.
// The returned DSN targets that database and cleanup removes it.
func ProvisionMySQL(
	ctx context.Context,
	administrativeDSN string,
) (databaseDSN string, cleanup func() error, err error) {
	configuration, err := mysql.ParseDSN(administrativeDSN)
	if err != nil {
		return "", nil, fmt.Errorf("parse MySQL administrative DSN: %w", err)
	}
	configuration.DBName = ""
	configuration.ParseTime = true
	administrativeDB, err := sql.Open("mysql", configuration.FormatDSN())
	if err != nil {
		return "", nil, fmt.Errorf("open MySQL administrative connection: %w", err)
	}
	if err := administrativeDB.PingContext(ctx); err != nil {
		_ = administrativeDB.Close()
		return "", nil, fmt.Errorf("ping MySQL administrative connection: %w", err)
	}

	databaseName, err := randomDatabaseName()
	if err != nil {
		_ = administrativeDB.Close()
		return "", nil, err
	}
	if _, err := administrativeDB.ExecContext(
		ctx,
		"CREATE DATABASE `"+databaseName+"` CHARACTER SET utf8mb4",
	); err != nil {
		_ = administrativeDB.Close()
		return "", nil, fmt.Errorf("create MySQL contract database: %w", err)
	}

	configuration.DBName = databaseName
	cleanup = func() error {
		_, dropErr := administrativeDB.Exec("DROP DATABASE IF EXISTS `" + databaseName + "`")
		closeErr := administrativeDB.Close()
		if dropErr != nil {
			return fmt.Errorf("drop MySQL contract database: %w", dropErr)
		}
		if closeErr != nil {
			return fmt.Errorf("close MySQL administrative connection: %w", closeErr)
		}
		return nil
	}
	return configuration.FormatDSN(), cleanup, nil
}

func randomDatabaseName() (string, error) {
	var suffix [8]byte
	if _, err := rand.Read(suffix[:]); err != nil {
		return "", fmt.Errorf("generate MySQL contract database name: %w", err)
	}
	return "ianvs_contract_" + hex.EncodeToString(suffix[:]), nil
}
