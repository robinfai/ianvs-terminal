package database

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"slices"
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
const CurrentSchemaVersion uint = 1

const (
	currentMetadataFormatVersion uint = 1
	schemaStateInitializing           = "initializing"
	schemaStateReady                  = "ready"
	mysqlMigrationLockTimeout         = 15 * time.Second
	sqliteBusyTimeout                 = 5 * time.Second
	sqliteMigrationAttempts           = 4
	mysqlTableOptions                 = "ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin"
	mysqlTableEngine                  = "InnoDB"
	mysqlCharacterSet                 = "utf8mb4"
	mysqlTableCollation               = "utf8mb4_bin"
)

type schemaMetadata struct {
	ID            uint      `gorm:"primaryKey;autoIncrement:false"`
	FormatVersion uint      `gorm:"not null"`
	SchemaVersion uint      `gorm:"not null"`
	ContractID    string    `gorm:"size:64;not null"`
	State         string    `gorm:"size:16;not null"`
	NextTable     uint      `gorm:"not null"`
	InitializedAt time.Time `gorm:"not null"`
	ReadyAt       *time.Time
}

func (schemaMetadata) TableName() string { return "schema_metadata" }

type columnContract struct {
	name       string
	kind       string
	logicalMax int64
	nullable   bool
	primaryKey bool
	autoSQLite bool
	autoMySQL  bool
}

type indexContract struct {
	columns []string
	unique  bool
}

type mysqlIndexColumn struct {
	IndexName  string         `gorm:"column:index_name"`
	NonUnique  int64          `gorm:"column:non_unique"`
	Sequence   int64          `gorm:"column:seq_in_index"`
	ColumnName sql.NullString `gorm:"column:column_name"`
	Collation  sql.NullString `gorm:"column:collation"`
	SubPart    sql.NullInt64  `gorm:"column:sub_part"`
	IndexType  string         `gorm:"column:index_type"`
	Expression sql.NullString `gorm:"column:expression"`
}

type mysqlColumnStorage struct {
	ColumnType           string         `gorm:"column:column_type"`
	CharacterSet         sql.NullString `gorm:"column:character_set_name"`
	Collation            sql.NullString `gorm:"column:collation_name"`
	DefaultValue         sql.NullString `gorm:"column:column_default"`
	Extra                string         `gorm:"column:extra"`
	GenerationExpression string         `gorm:"column:generation_expression"`
}

type mysqlTableStorage struct {
	Engine    sql.NullString `gorm:"column:engine"`
	Collation sql.NullString `gorm:"column:table_collation"`
}

type mysqlTableConstraint struct {
	Name string `gorm:"column:constraint_name"`
	Type string `gorm:"column:constraint_type"`
}

type sqliteIndex struct {
	Sequence int64  `gorm:"column:seq"`
	Name     string `gorm:"column:name"`
	Unique   int64  `gorm:"column:unique"`
	Origin   string `gorm:"column:origin"`
	Partial  int64  `gorm:"column:partial"`
}

type sqliteIndexColumn struct {
	Sequence int64          `gorm:"column:seqno"`
	CID      int64          `gorm:"column:cid"`
	Name     sql.NullString `gorm:"column:name"`
	Desc     int64          `gorm:"column:desc"`
	Coll     sql.NullString `gorm:"column:coll"`
	Key      int64          `gorm:"column:key"`
}

type sqliteTableColumn struct {
	Name         string         `gorm:"column:name"`
	DefaultValue sql.NullString `gorm:"column:dflt_value"`
	Hidden       int64          `gorm:"column:hidden"`
}

var sqliteCheckConstraintPattern = regexp.MustCompile(`(?i)\bCHECK\s*\(`)

type tableContract struct {
	name    string
	model   any
	columns []columnContract
	indexes map[string]indexContract
}

var metadataTableContract = tableContract{
	name:  "schema_metadata",
	model: &schemaMetadata{},
	columns: []columnContract{
		{name: "id", kind: "integer", primaryKey: true},
		{name: "format_version", kind: "integer"},
		{name: "schema_version", kind: "integer"},
		{name: "contract_id", kind: "string", logicalMax: 64},
		{name: "state", kind: "string", logicalMax: 16},
		{name: "next_table", kind: "integer"},
		{name: "initialized_at", kind: "datetime"},
		{name: "ready_at", kind: "datetime", nullable: true},
	},
}

var currentTableContracts = []tableContract{
	{
		name:  "users",
		model: &model.User{},
		columns: []columnContract{
			{name: "id", kind: "string", logicalMax: 36, primaryKey: true},
			{name: "username", kind: "string", logicalMax: 191},
			{name: "password_hash", kind: "string", logicalMax: 255, nullable: true},
			{name: "created_at", kind: "datetime"},
			{name: "updated_at", kind: "datetime"},
		},
		indexes: map[string]indexContract{
			"idx_users_username": {columns: []string{"username"}, unique: true},
		},
	},
	{
		name:  "auth_operations",
		model: &model.AuthOperation{},
		columns: []columnContract{
			{name: "operation_hash", kind: "string", logicalMax: 64, primaryKey: true},
			{name: "kind", kind: "string", logicalMax: 16},
			{name: "state", kind: "string", logicalMax: 16},
			{name: "user_id", kind: "string", logicalMax: 36, nullable: true},
			{name: "expires_at", kind: "datetime"},
			{name: "created_at", kind: "datetime"},
			{name: "updated_at", kind: "datetime"},
		},
		indexes: map[string]indexContract{
			"idx_auth_operations_user_id":    {columns: []string{"user_id"}},
			"idx_auth_operations_expires_at": {columns: []string{"expires_at"}},
		},
	},
	{
		name:  "auth_tokens",
		model: &model.AuthToken{},
		columns: []columnContract{
			{name: "id", kind: "string", logicalMax: 36, primaryKey: true},
			{name: "user_id", kind: "string", logicalMax: 36},
			{name: "token_hash", kind: "string", logicalMax: 64},
			{name: "operation_hash", kind: "string", logicalMax: 64},
			{name: "expires_at", kind: "datetime"},
			{name: "created_at", kind: "datetime"},
		},
		indexes: map[string]indexContract{
			"idx_auth_tokens_user_id":        {columns: []string{"user_id"}},
			"idx_auth_tokens_token_hash":     {columns: []string{"token_hash"}, unique: true},
			"idx_auth_tokens_operation_hash": {columns: []string{"operation_hash"}, unique: true},
			"idx_auth_tokens_expires_at":     {columns: []string{"expires_at"}},
		},
	},
	{
		name:  "resources",
		model: &model.Resource{},
		columns: []columnContract{
			{name: "id", kind: "string", logicalMax: 36, primaryKey: true},
			{name: "user_id", kind: "string", logicalMax: 36},
			{name: "kind", kind: "string", logicalMax: 64},
			{name: "external_id", kind: "string", logicalMax: 191},
			{name: "plain_json", kind: "string", logicalMax: 4194304},
			{name: "sensitive_json", kind: "string", logicalMax: 6291456, nullable: true},
			{name: "revision", kind: "integer"},
			{name: "source_id", kind: "string", logicalMax: 64, nullable: true},
			{name: "source_revision", kind: "integer"},
			{name: "origin_updated_at", kind: "datetime"},
			{name: "deleted", kind: "boolean"},
			{name: "deleted_at", kind: "datetime", nullable: true},
			{name: "created_at", kind: "datetime"},
			{name: "updated_at", kind: "datetime"},
		},
		indexes: map[string]indexContract{
			"idx_resource_owner_key":          {columns: []string{"user_id", "kind", "external_id"}, unique: true},
			"idx_resources_user_id":           {columns: []string{"user_id"}},
			"idx_resources_kind":              {columns: []string{"kind"}},
			"idx_resources_origin_updated_at": {columns: []string{"origin_updated_at"}},
			"idx_resources_deleted":           {columns: []string{"deleted"}},
			"idx_resources_deleted_at":        {columns: []string{"deleted_at"}},
		},
	},
	{
		name:  "settings",
		model: &model.Setting{},
		columns: []columnContract{
			{name: "key", kind: "string", logicalMax: 191, primaryKey: true},
			{name: "value", kind: "string", logicalMax: 4194304},
			{name: "created_at", kind: "datetime"},
			{name: "updated_at", kind: "datetime"},
		},
	},
}

// bootstrapStepHook is nil in product builds and gives package tests a precise
// failure point around non-transactional DDL.
var bootstrapStepHook func(string) error

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
		// the fresh bootstrap writes its metadata only after DDL succeeds.
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
	if !db.Migrator().HasTable(&schemaMetadata{}) {
		tables, err := db.Migrator().GetTables()
		if err != nil {
			return fmt.Errorf("inspect database before current schema bootstrap: %w", err)
		}
		if len(tables) != 0 {
			return errors.New("database is not empty and has no current schema metadata; clear the unreleased data before starting this backend")
		}
		if err := createCurrentTable(db, &schemaMetadata{}); err != nil {
			return fmt.Errorf("create current schema metadata table: %w", err)
		}
		if err := runBootstrapStepHook("after-metadata-table"); err != nil {
			return err
		}
	}
	if err := validateTable(db, metadataTableContract); err != nil {
		return fmt.Errorf("validate current schema metadata table: %w", err)
	}
	metadata, err := loadOrBeginCurrentBootstrap(db)
	if err != nil {
		return err
	}
	switch metadata.State {
	case schemaStateInitializing:
		return resumeCurrentBootstrap(db, metadata)
	case schemaStateReady:
		if metadata.NextTable != uint(len(currentTableContracts)) || metadata.ReadyAt == nil {
			return errors.New("ready current schema metadata has invalid progress")
		}
		return validateCurrentSchema(db)
	default:
		return fmt.Errorf("unsupported current schema state %q", metadata.State)
	}
}

func loadOrBeginCurrentBootstrap(db *gorm.DB) (schemaMetadata, error) {
	var count int64
	if err := db.Model(&schemaMetadata{}).Count(&count).Error; err != nil {
		return schemaMetadata{}, fmt.Errorf("count current schema metadata rows: %w", err)
	}
	if count > 1 {
		return schemaMetadata{}, fmt.Errorf("database must contain at most one current schema metadata row, found %d", count)
	}
	if count == 0 {
		if err := validateExactTableSet(db, map[string]bool{metadataTableContract.name: true}); err != nil {
			return schemaMetadata{}, fmt.Errorf("recover empty current schema metadata: %w", err)
		}
		metadata := schemaMetadata{
			ID:            1,
			FormatVersion: currentMetadataFormatVersion,
			SchemaVersion: CurrentSchemaVersion,
			ContractID:    CurrentSchemaContractID(),
			State:         schemaStateInitializing,
			NextTable:     0,
			InitializedAt: time.Now().UTC(),
		}
		if err := db.Create(&metadata).Error; err != nil {
			return schemaMetadata{}, fmt.Errorf("begin current schema bootstrap: %w", err)
		}
		if err := runBootstrapStepHook("after-metadata-record"); err != nil {
			return schemaMetadata{}, err
		}
		return metadata, nil
	}
	var metadata schemaMetadata
	if err := db.Where("id = ?", 1).First(&metadata).Error; err != nil {
		return schemaMetadata{}, fmt.Errorf("read current schema metadata: %w", err)
	}
	if err := validateCurrentMetadata(metadata); err != nil {
		return schemaMetadata{}, err
	}
	return metadata, nil
}

func validateCurrentMetadata(metadata schemaMetadata) error {
	if metadata.FormatVersion != currentMetadataFormatVersion {
		return fmt.Errorf(
			"unsupported schema metadata format %d; expected %d",
			metadata.FormatVersion,
			currentMetadataFormatVersion,
		)
	}
	if metadata.SchemaVersion > CurrentSchemaVersion {
		return fmt.Errorf(
			"database schema version %d is newer than supported version %d",
			metadata.SchemaVersion,
			CurrentSchemaVersion,
		)
	}
	if metadata.SchemaVersion != CurrentSchemaVersion || metadata.ContractID != CurrentSchemaContractID() {
		return errors.New("database metadata does not match the current schema contract; clear the unreleased data before starting this backend")
	}
	if metadata.NextTable > uint(len(currentTableContracts)) {
		return fmt.Errorf("current schema bootstrap progress %d is out of range", metadata.NextTable)
	}
	if metadata.State == schemaStateInitializing && metadata.ReadyAt != nil {
		return errors.New("initializing current schema metadata must not have ready_at")
	}
	return nil
}

func resumeCurrentBootstrap(db *gorm.DB, metadata schemaMetadata) error {
	if metadata.ReadyAt != nil {
		return errors.New("initializing current schema metadata must not have ready_at")
	}
	allowedTables := map[string]bool{metadataTableContract.name: true}
	for index, contract := range currentTableContracts {
		if uint(index) <= metadata.NextTable {
			allowedTables[contract.name] = true
		}
	}
	tables, err := db.Migrator().GetTables()
	if err != nil {
		return fmt.Errorf("inspect initializing current schema tables: %w", err)
	}
	for _, table := range tables {
		if !allowedTables[strings.ToLower(table)] {
			return fmt.Errorf("initializing current schema contains unexpected future or foreign table %q", table)
		}
	}
	for tableIndex, contract := range currentTableContracts {
		index := uint(tableIndex)
		exists := db.Migrator().HasTable(contract.model)
		switch {
		case index < metadata.NextTable:
			if !exists {
				return fmt.Errorf("initializing current schema is missing completed table %q", contract.name)
			}
			if err := validateTable(db, contract); err != nil {
				return fmt.Errorf("validate completed current table %q: %w", contract.name, err)
			}
		case index == metadata.NextTable:
			if !exists {
				if err := createCurrentTable(db, contract.model); err != nil {
					return fmt.Errorf("create current schema table %q: %w", contract.name, err)
				}
				if err := runBootstrapStepHook("after-create:" + contract.name); err != nil {
					return err
				}
			}
			if err := validateTable(db, contract); err != nil {
				return fmt.Errorf("validate newly created current table %q: %w", contract.name, err)
			}
			result := db.Model(&schemaMetadata{}).
				Where("id = ? AND state = ? AND next_table = ?", 1, schemaStateInitializing, index).
				Update("next_table", index+1)
			if result.Error != nil {
				return fmt.Errorf("advance current schema bootstrap after %q: %w", contract.name, result.Error)
			}
			if result.RowsAffected != 1 {
				return fmt.Errorf("advance current schema bootstrap after %q: metadata changed unexpectedly", contract.name)
			}
			metadata.NextTable = index + 1
		case exists:
			return fmt.Errorf("initializing current schema contains unexpected future table %q", contract.name)
		}
	}
	if err := validateCurrentSchema(db); err != nil {
		return err
	}
	readyAt := time.Now().UTC()
	result := db.Model(&schemaMetadata{}).
		Where(
			"id = ? AND state = ? AND next_table = ?",
			1,
			schemaStateInitializing,
			len(currentTableContracts),
		).
		Updates(map[string]any{"state": schemaStateReady, "ready_at": readyAt})
	if result.Error != nil {
		return fmt.Errorf("mark current schema ready: %w", result.Error)
	}
	if result.RowsAffected != 1 {
		return errors.New("mark current schema ready: metadata changed unexpectedly")
	}
	return nil
}

func validateCurrentSchema(db *gorm.DB) error {
	expectedTables := map[string]bool{metadataTableContract.name: true}
	if err := validateTable(db, metadataTableContract); err != nil {
		return fmt.Errorf("validate current metadata table: %w", err)
	}
	for _, contract := range currentTableContracts {
		expectedTables[contract.name] = true
		if err := validateTable(db, contract); err != nil {
			return fmt.Errorf("validate current table %q: %w", contract.name, err)
		}
	}
	return validateExactTableSet(db, expectedTables)
}

func validateTable(db *gorm.DB, contract tableContract) error {
	if !db.Migrator().HasTable(contract.model) {
		return errors.New("table is missing")
	}
	if db.Dialector.Name() == "mysql" {
		if err := validateMySQLTableStructure(db, contract); err != nil {
			return err
		}
	}
	columns, err := db.Migrator().ColumnTypes(contract.model)
	if err != nil {
		return fmt.Errorf("inspect columns: %w", err)
	}
	actualColumns := make(map[string]gorm.ColumnType, len(columns))
	for _, column := range columns {
		actualColumns[strings.ToLower(column.Name())] = column
	}
	if len(actualColumns) != len(contract.columns) {
		return fmt.Errorf("column count %d does not match current contract %d", len(actualColumns), len(contract.columns))
	}
	for _, expected := range contract.columns {
		actual, found := actualColumns[expected.name]
		if !found {
			return fmt.Errorf("column %q is missing", expected.name)
		}
		primary, known := actual.PrimaryKey()
		if !known || primary != expected.primaryKey {
			return fmt.Errorf("column %q primary-key constraint does not match current contract", expected.name)
		}
		if !expected.primaryKey {
			nullable, known := actual.Nullable()
			if !known || nullable != expected.nullable {
				return fmt.Errorf("column %q nullability does not match current contract", expected.name)
			}
		}
		if err := validateColumnStorage(db, contract.name, actual, expected); err != nil {
			return fmt.Errorf("column %q storage does not match current contract: %w", expected.name, err)
		}
	}
	if db.Dialector.Name() == "sqlite" {
		var definition string
		if err := db.Raw(
			"SELECT sql FROM sqlite_master WHERE type = ? AND name = ?",
			"table",
			contract.name,
		).Scan(&definition).Error; err != nil {
			return fmt.Errorf("inspect SQLite table definition: %w", err)
		}
		expectsAuto := false
		for _, column := range contract.columns {
			expectsAuto = expectsAuto || column.autoSQLite
		}
		if strings.Contains(strings.ToUpper(definition), "AUTOINCREMENT") != expectsAuto {
			return errors.New("SQLite AUTOINCREMENT contract does not match")
		}
		if err := validateSQLiteTableStructure(db, contract, definition); err != nil {
			return err
		}
	}
	if db.Dialector.Name() == "mysql" {
		return validateMySQLIndexes(db, contract)
	}
	if db.Dialector.Name() == "sqlite" {
		return validateSQLiteIndexes(db, contract)
	}
	return validateMigratorIndexes(db, contract)
}

func createCurrentTable(db *gorm.DB, model any) error {
	if db.Dialector.Name() == "mysql" {
		return db.Set("gorm:table_options", mysqlTableOptions).Migrator().CreateTable(model)
	}
	return db.Migrator().CreateTable(model)
}

func validateMySQLTableStructure(db *gorm.DB, contract tableContract) error {
	table := contract.name
	var storage mysqlTableStorage
	if err := db.Raw(
		`SELECT ENGINE AS engine, TABLE_COLLATION AS table_collation
		   FROM information_schema.TABLES
		  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?`,
		table,
	).Scan(&storage).Error; err != nil {
		return fmt.Errorf("inspect MySQL table storage: %w", err)
	}
	if !storage.Engine.Valid || !strings.EqualFold(storage.Engine.String, mysqlTableEngine) {
		return fmt.Errorf("MySQL table engine %q does not equal %q", storage.Engine.String, mysqlTableEngine)
	}
	if !storage.Collation.Valid || !strings.EqualFold(storage.Collation.String, mysqlTableCollation) {
		return fmt.Errorf("MySQL table collation %q does not equal %q", storage.Collation.String, mysqlTableCollation)
	}
	var triggerCount int64
	if err := db.Raw(
		`SELECT COUNT(*) FROM information_schema.TRIGGERS
		  WHERE TRIGGER_SCHEMA = DATABASE() AND EVENT_OBJECT_TABLE = ?`,
		table,
	).Scan(&triggerCount).Error; err != nil {
		return fmt.Errorf("inspect MySQL triggers: %w", err)
	}
	if triggerCount != 0 {
		return fmt.Errorf("MySQL table has %d forbidden trigger(s)", triggerCount)
	}
	var constraints []mysqlTableConstraint
	if err := db.Raw(
		`SELECT CONSTRAINT_NAME AS constraint_name, CONSTRAINT_TYPE AS constraint_type
		   FROM information_schema.TABLE_CONSTRAINTS
		  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = ?
		  ORDER BY CONSTRAINT_NAME`,
		table,
	).Scan(&constraints).Error; err != nil {
		return fmt.Errorf("inspect MySQL table constraints: %w", err)
	}
	expected := map[string]string{"primary": "PRIMARY KEY"}
	for name, index := range contract.indexes {
		if index.unique {
			expected[name] = "UNIQUE"
		}
	}
	for _, constraint := range constraints {
		name := strings.ToLower(constraint.Name)
		want, found := expected[name]
		if !found || !strings.EqualFold(constraint.Type, want) {
			return fmt.Errorf("MySQL constraint %q type %q is not part of the current contract", constraint.Name, constraint.Type)
		}
		delete(expected, name)
	}
	if len(expected) != 0 {
		return errors.New("MySQL constraint set does not match current contract")
	}
	return nil
}

func validateSQLiteTableStructure(db *gorm.DB, contract tableContract, definition string) error {
	var columns []sqliteTableColumn
	if err := db.Raw(
		"SELECT name, dflt_value, hidden FROM pragma_table_xinfo(?) ORDER BY cid",
		contract.name,
	).Scan(&columns).Error; err != nil {
		return fmt.Errorf("inspect SQLite extended columns: %w", err)
	}
	if len(columns) != len(contract.columns) {
		return fmt.Errorf("SQLite extended column count %d does not match current contract %d", len(columns), len(contract.columns))
	}
	for index, column := range columns {
		if !strings.EqualFold(column.Name, contract.columns[index].name) {
			return fmt.Errorf("SQLite extended column %d does not match current contract", index+1)
		}
		if column.DefaultValue.Valid {
			return fmt.Errorf("SQLite column %q has a forbidden default", column.Name)
		}
		if column.Hidden != 0 {
			return fmt.Errorf("SQLite column %q is hidden or generated", column.Name)
		}
	}
	var foreignKeyCount int64
	if err := db.Raw("SELECT COUNT(*) FROM pragma_foreign_key_list(?)", contract.name).Scan(&foreignKeyCount).Error; err != nil {
		return fmt.Errorf("inspect SQLite foreign keys: %w", err)
	}
	if foreignKeyCount != 0 {
		return fmt.Errorf("SQLite table has %d forbidden foreign key(s)", foreignKeyCount)
	}
	var triggerCount int64
	if err := db.Raw(
		"SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND tbl_name = ?",
		contract.name,
	).Scan(&triggerCount).Error; err != nil {
		return fmt.Errorf("inspect SQLite triggers: %w", err)
	}
	if triggerCount != 0 {
		return fmt.Errorf("SQLite table has %d forbidden trigger(s)", triggerCount)
	}
	if sqliteCheckConstraintPattern.MatchString(definition) {
		return errors.New("SQLite table has a forbidden CHECK constraint")
	}
	return nil
}

func validateMigratorIndexes(db *gorm.DB, contract tableContract) error {
	indexes, err := db.Migrator().GetIndexes(contract.model)
	if err != nil {
		return fmt.Errorf("inspect indexes: %w", err)
	}
	actualIndexes := make(map[string]gorm.Index)
	for _, index := range indexes {
		primary, known := index.PrimaryKey()
		if known && primary {
			continue
		}
		actualIndexes[strings.ToLower(index.Name())] = index
	}
	if len(actualIndexes) != len(contract.indexes) {
		return fmt.Errorf("index count %d does not match current contract %d", len(actualIndexes), len(contract.indexes))
	}
	for name, expected := range contract.indexes {
		actual, found := actualIndexes[name]
		if !found {
			return fmt.Errorf("index %q is missing", name)
		}
		if !equalFoldedStrings(actual.Columns(), expected.columns) {
			return fmt.Errorf("index %q columns do not match current contract", name)
		}
		unique, known := actual.Unique()
		if !known || unique != expected.unique {
			return fmt.Errorf("index %q uniqueness does not match current contract", name)
		}
	}
	return nil
}

func validateMySQLIndexes(db *gorm.DB, contract tableContract) error {
	var rows []mysqlIndexColumn
	if err := db.Raw(
		`SELECT INDEX_NAME AS index_name,
		        NON_UNIQUE AS non_unique,
		        SEQ_IN_INDEX AS seq_in_index,
		        COLUMN_NAME AS column_name,
		        COLLATION AS collation,
		        SUB_PART AS sub_part,
		        INDEX_TYPE AS index_type,
		        EXPRESSION AS expression
		   FROM information_schema.STATISTICS
		  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
		  ORDER BY INDEX_NAME, SEQ_IN_INDEX`,
		contract.name,
	).Scan(&rows).Error; err != nil {
		return fmt.Errorf("inspect MySQL concrete indexes: %w", err)
	}

	expectedIndexes := make(map[string]indexContract, len(contract.indexes)+1)
	for name, expected := range contract.indexes {
		expectedIndexes[name] = expected
	}
	primaryColumns := make([]string, 0, 1)
	for _, column := range contract.columns {
		if column.primaryKey {
			primaryColumns = append(primaryColumns, column.name)
		}
	}
	if len(primaryColumns) > 0 {
		expectedIndexes["primary"] = indexContract{columns: primaryColumns, unique: true}
	}

	actualIndexes := make(map[string][]mysqlIndexColumn, len(expectedIndexes))
	for _, row := range rows {
		name := strings.ToLower(row.IndexName)
		actualIndexes[name] = append(actualIndexes[name], row)
	}
	if len(actualIndexes) != len(expectedIndexes) {
		return fmt.Errorf("MySQL index count %d does not match current contract %d", len(actualIndexes), len(expectedIndexes))
	}
	for name, expected := range expectedIndexes {
		actual, found := actualIndexes[name]
		if !found {
			return fmt.Errorf("MySQL index %q is missing", name)
		}
		if len(actual) != len(expected.columns) {
			return fmt.Errorf("MySQL index %q column count does not match current contract", name)
		}
		for position, row := range actual {
			if row.Sequence != int64(position+1) {
				return fmt.Errorf("MySQL index %q sequence does not match current contract", name)
			}
			if !row.ColumnName.Valid || !strings.EqualFold(row.ColumnName.String, expected.columns[position]) {
				return fmt.Errorf("MySQL index %q column %d does not match current contract", name, position+1)
			}
			if row.SubPart.Valid {
				return fmt.Errorf("MySQL index %q column %d uses a forbidden prefix length", name, position+1)
			}
			if !row.Collation.Valid || !strings.EqualFold(row.Collation.String, "A") {
				return fmt.Errorf("MySQL index %q column %d sort direction does not match current contract", name, position+1)
			}
			if !strings.EqualFold(row.IndexType, "BTREE") {
				return fmt.Errorf("MySQL index %q type %q does not match current contract", name, row.IndexType)
			}
			if row.Expression.Valid {
				return fmt.Errorf("MySQL index %q column %d is an unsupported expression", name, position+1)
			}
			wantNonUnique := int64(1)
			if expected.unique {
				wantNonUnique = 0
			}
			if row.NonUnique != wantNonUnique {
				return fmt.Errorf("MySQL index %q uniqueness does not match current contract", name)
			}
		}
	}
	return nil
}

func validateSQLiteIndexes(db *gorm.DB, contract tableContract) error {
	var indexes []sqliteIndex
	if err := db.Raw(
		"SELECT seq, name, `unique`, origin, partial FROM pragma_index_list(?) ORDER BY seq",
		contract.name,
	).Scan(&indexes).Error; err != nil {
		return fmt.Errorf("inspect SQLite concrete indexes: %w", err)
	}

	primaryColumns := make([]string, 0, 1)
	primaryNeedsIndex := false
	for _, column := range contract.columns {
		if column.primaryKey {
			primaryColumns = append(primaryColumns, column.name)
			primaryNeedsIndex = column.kind != "integer"
		}
	}
	wantCount := len(contract.indexes)
	if primaryNeedsIndex {
		wantCount++
	}
	if len(indexes) != wantCount {
		return fmt.Errorf("SQLite index count %d does not match current contract %d", len(indexes), wantCount)
	}

	seen := make(map[string]bool, len(contract.indexes))
	seenPrimary := false
	for _, index := range indexes {
		if index.Partial != 0 {
			return fmt.Errorf("SQLite index %q is a forbidden partial index", index.Name)
		}
		var expected indexContract
		switch strings.ToLower(index.Origin) {
		case "pk":
			if !primaryNeedsIndex || seenPrimary {
				return fmt.Errorf("SQLite index %q is an unexpected primary-key index", index.Name)
			}
			seenPrimary = true
			expected = indexContract{columns: primaryColumns, unique: true}
		case "c":
			name := strings.ToLower(index.Name)
			var found bool
			expected, found = contract.indexes[name]
			if !found || seen[name] {
				return fmt.Errorf("SQLite index %q is not part of the current contract", index.Name)
			}
			seen[name] = true
		default:
			return fmt.Errorf("SQLite index %q has unsupported origin %q", index.Name, index.Origin)
		}
		wantUnique := int64(0)
		if expected.unique {
			wantUnique = 1
		}
		if index.Unique != wantUnique {
			return fmt.Errorf("SQLite index %q uniqueness does not match current contract", index.Name)
		}
		if err := validateSQLiteIndexColumns(db, index.Name, expected.columns); err != nil {
			return err
		}
	}
	if seenPrimary != primaryNeedsIndex || len(seen) != len(contract.indexes) {
		return errors.New("SQLite index set does not match current contract")
	}
	return nil
}

func validateSQLiteIndexColumns(db *gorm.DB, indexName string, expected []string) error {
	var rows []sqliteIndexColumn
	if err := db.Raw(
		"SELECT seqno, cid, name, `desc`, coll, key FROM pragma_index_xinfo(?) ORDER BY seqno",
		indexName,
	).Scan(&rows).Error; err != nil {
		return fmt.Errorf("inspect SQLite index %q columns: %w", indexName, err)
	}
	keyRows := make([]sqliteIndexColumn, 0, len(expected))
	for _, row := range rows {
		if row.Key == 1 {
			keyRows = append(keyRows, row)
		}
	}
	if len(keyRows) != len(expected) {
		return fmt.Errorf("SQLite index %q key-column count does not match current contract", indexName)
	}
	for position, row := range keyRows {
		if row.Sequence != int64(position) || row.CID < 0 || !row.Name.Valid ||
			!strings.EqualFold(row.Name.String, expected[position]) {
			return fmt.Errorf("SQLite index %q column %d does not match current contract", indexName, position+1)
		}
		if row.Desc != 0 {
			return fmt.Errorf("SQLite index %q column %d uses a forbidden descending order", indexName, position+1)
		}
		if !row.Coll.Valid || !strings.EqualFold(row.Coll.String, "BINARY") {
			return fmt.Errorf("SQLite index %q column %d collation does not match current contract", indexName, position+1)
		}
	}
	return nil
}

func validateColumnStorage(db *gorm.DB, table string, actual gorm.ColumnType, expected columnContract) error {
	driver := db.Dialector.Name()
	databaseType := strings.ToLower(actual.DatabaseTypeName())
	if driver == "sqlite" {
		expectedType := map[string]string{
			"string": "text", "integer": "integer", "datetime": "datetime", "boolean": "numeric",
		}[expected.kind]
		if databaseType != expectedType {
			return fmt.Errorf("SQLite database type %q does not equal %q", databaseType, expectedType)
		}
		return nil
	}
	if driver != "mysql" {
		return fmt.Errorf("unsupported schema validation dialect %q", driver)
	}
	var storage mysqlColumnStorage
	if err := db.Raw(
		`SELECT COLUMN_TYPE AS column_type,
		        CHARACTER_SET_NAME AS character_set_name,
		        COLLATION_NAME AS collation_name,
		        COLUMN_DEFAULT AS column_default,
		        EXTRA AS extra,
		        GENERATION_EXPRESSION AS generation_expression
		   FROM information_schema.COLUMNS
		  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?`,
		table,
		expected.name,
	).Scan(&storage).Error; err != nil {
		return fmt.Errorf("inspect MySQL concrete column type: %w", err)
	}
	want := mysqlColumnType(table, expected)
	if strings.ToLower(storage.ColumnType) != want {
		return fmt.Errorf("MySQL column type %q does not equal %q", storage.ColumnType, want)
	}
	if expected.kind == "string" {
		if !storage.CharacterSet.Valid || !strings.EqualFold(storage.CharacterSet.String, mysqlCharacterSet) {
			return fmt.Errorf("MySQL character set %q does not equal %q", storage.CharacterSet.String, mysqlCharacterSet)
		}
		if !storage.Collation.Valid || !strings.EqualFold(storage.Collation.String, mysqlTableCollation) {
			return fmt.Errorf("MySQL collation %q does not equal %q", storage.Collation.String, mysqlTableCollation)
		}
	} else if storage.CharacterSet.Valid || storage.Collation.Valid {
		return errors.New("non-string MySQL column unexpectedly has character storage metadata")
	}
	if storage.DefaultValue.Valid {
		return fmt.Errorf("MySQL column has forbidden default %q", storage.DefaultValue.String)
	}
	wantExtra := ""
	if expected.autoMySQL {
		wantExtra = "auto_increment"
	}
	if !strings.EqualFold(storage.Extra, wantExtra) {
		return fmt.Errorf("MySQL EXTRA metadata %q does not equal %q", storage.Extra, wantExtra)
	}
	if storage.GenerationExpression != "" {
		return errors.New("MySQL column has a forbidden generation expression")
	}
	return nil
}

func mysqlColumnType(table string, column columnContract) string {
	switch column.kind {
	case "string":
		if column.logicalMax >= 65536 && column.logicalMax <= 1<<24 {
			return "mediumtext"
		}
		return fmt.Sprintf("varchar(%d)", column.logicalMax)
	case "integer":
		if table == metadataTableContract.name {
			return "bigint unsigned"
		}
		return "bigint"
	case "datetime":
		return "datetime(3)"
	case "boolean":
		return "tinyint(1)"
	default:
		return ""
	}
}

// CurrentSchemaContractID fingerprints the only accepted unreleased schema,
// including logical field capacities even where SQLite represents strings as
// unbounded TEXT and application validation enforces the byte limit.
func CurrentSchemaContractID() string {
	hash := sha256.New()
	_, _ = fmt.Fprintf(hash, "mysql-table:%s:%s:%s\n", mysqlTableEngine, mysqlCharacterSet, mysqlTableCollation)
	contracts := append([]tableContract{metadataTableContract}, currentTableContracts...)
	for _, contract := range contracts {
		_, _ = fmt.Fprintf(hash, "table:%s\n", contract.name)
		for _, column := range contract.columns {
			_, _ = fmt.Fprintf(
				hash,
				"column:%s:%s:%d:%t:%t:%t:%t\n",
				column.name,
				column.kind,
				column.logicalMax,
				column.nullable,
				column.primaryKey,
				column.autoSQLite,
				column.autoMySQL,
			)
		}
		indexNames := make([]string, 0, len(contract.indexes))
		for name := range contract.indexes {
			indexNames = append(indexNames, name)
		}
		slices.Sort(indexNames)
		for _, name := range indexNames {
			index := contract.indexes[name]
			_, _ = fmt.Fprintf(hash, "index:%s:%s:%t\n", name, strings.Join(index.columns, ","), index.unique)
		}
	}
	return hex.EncodeToString(hash.Sum(nil))
}

func validateExactTableSet(db *gorm.DB, expected map[string]bool) error {
	tables, err := db.Migrator().GetTables()
	if err != nil {
		return fmt.Errorf("inspect database tables: %w", err)
	}
	actual := make(map[string]bool, len(tables))
	for _, table := range tables {
		actual[strings.ToLower(table)] = true
	}
	if len(actual) != len(expected) {
		return fmt.Errorf("table count %d does not match current contract %d", len(actual), len(expected))
	}
	for table := range expected {
		if !actual[table] {
			return fmt.Errorf("table %q is missing", table)
		}
	}
	return nil
}

func equalFoldedStrings(actual, expected []string) bool {
	if len(actual) != len(expected) {
		return false
	}
	for index := range actual {
		if !strings.EqualFold(actual[index], expected[index]) {
			return false
		}
	}
	return true
}

func runBootstrapStepHook(step string) error {
	if bootstrapStepHook == nil {
		return nil
	}
	if err := bootstrapStepHook(step); err != nil {
		return fmt.Errorf("current schema bootstrap interrupted at %s: %w", step, err)
	}
	return nil
}

func currentSchemaIsApplied(db *gorm.DB) (bool, error) {
	if !db.Migrator().HasTable(&schemaMetadata{}) {
		return false, nil
	}
	if err := validateTable(db, metadataTableContract); err != nil {
		return false, fmt.Errorf("validate current schema metadata table: %w", err)
	}
	var count int64
	if err := db.Model(&schemaMetadata{}).Count(&count).Error; err != nil {
		return false, fmt.Errorf("count current schema metadata rows: %w", err)
	}
	if count == 0 {
		return false, nil
	}
	if count != 1 {
		return false, fmt.Errorf("database must contain exactly one current schema metadata row, found %d", count)
	}
	var metadata schemaMetadata
	if err := db.Where("id = ?", 1).First(&metadata).Error; err != nil {
		return false, fmt.Errorf("read current schema metadata: %w", err)
	}
	if err := validateCurrentMetadata(metadata); err != nil {
		return false, err
	}
	if metadata.State != schemaStateReady {
		return false, nil
	}
	if err := validateCurrentSchema(db); err != nil {
		return false, err
	}
	return true, nil
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
