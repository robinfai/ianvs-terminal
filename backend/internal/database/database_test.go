package database_test

import (
	"context"
	"database/sql"
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

func TestOpenBootstrapsOnlyCurrentSchema(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "current.db"))
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("database.Open() error = %v", err)
	}
	defer closeGormDB(t, db)

	for _, currentModel := range []any{
		&model.User{},
		&model.AuthToken{},
		&model.AuthOperation{},
		&model.Resource{},
		&model.Setting{},
	} {
		if !db.Migrator().HasTable(currentModel) {
			t.Fatalf("fresh current schema omitted table for %T", currentModel)
		}
	}
	var versions []uint
	if err := db.Table("schema_metadata").Order("schema_version").Pluck("schema_version", &versions).Error; err != nil {
		t.Fatalf("read schema metadata: %v", err)
	}
	if !equalVersions(versions, []uint{database.CurrentSchemaVersion}) {
		t.Fatalf("schema versions = %v, want [%d]", versions, database.CurrentSchemaVersion)
	}
	assertOperationHashNotNullable(t, db)
}

func TestOpenRejectsNonemptyDatabaseWithoutCurrentMetadata(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "noncurrent.db"))
	noncurrent, err := openUnversionedDatabase(cfg)
	if err != nil {
		t.Fatalf("open noncurrent database: %v", err)
	}
	if err := autoMigrateTestModels(noncurrent, &model.User{}); err != nil {
		t.Fatalf("create noncurrent table: %v", err)
	}
	closeGormDB(t, noncurrent)

	_, err = database.Open(cfg)
	if err == nil || !strings.Contains(err.Error(), "not empty") {
		t.Fatalf("database.Open() error = %v, want noncurrent database rejection", err)
	}
}

func TestOpenRejectsNonCurrentShapeWithoutMutatingIt(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "wrong-shape.db"))
	noncurrent, err := openUnversionedDatabase(cfg)
	if err != nil {
		t.Fatalf("open noncurrent database: %v", err)
	}
	if err := autoMigrateTestModels(noncurrent, &schemaMetadataTest{}, &model.User{}); err != nil {
		t.Fatalf("create noncurrent shape: %v", err)
	}
	readyAt := time.Now().UTC()
	if err := noncurrent.Create(currentSchemaMetadataTest("ready", 5, &readyAt)).Error; err != nil {
		t.Fatalf("record deceptive current version: %v", err)
	}
	closeGormDB(t, noncurrent)

	_, err = database.Open(cfg)
	if err == nil || !strings.Contains(err.Error(), `current table "auth_operations"`) {
		t.Fatalf("database.Open() error = %v, want current-shape rejection", err)
	}
	inspected, err := openUnversionedDatabase(cfg)
	if err != nil {
		t.Fatalf("reopen rejected database: %v", err)
	}
	defer closeGormDB(t, inspected)
	if inspected.Migrator().HasTable(&model.AuthOperation{}) {
		t.Fatal("rejected noncurrent database was mutated with current tables")
	}
}

func TestOpenRejectsNullableOperationHashInClaimedCurrentSchema(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "nullable-token.db"))
	noncurrent, err := openUnversionedDatabase(cfg)
	if err != nil {
		t.Fatalf("open malformed database: %v", err)
	}
	if err := autoMigrateTestModels(
		noncurrent,
		&schemaMetadataTest{},
		&model.User{},
		&nullableAuthTokenTest{},
		&model.AuthOperation{},
		&model.Resource{},
		&model.Setting{},
	); err != nil {
		t.Fatalf("create malformed current shape: %v", err)
	}
	readyAt := time.Now().UTC()
	if err := noncurrent.Create(currentSchemaMetadataTest("ready", 5, &readyAt)).Error; err != nil {
		t.Fatalf("record claimed current version: %v", err)
	}
	closeGormDB(t, noncurrent)

	_, err = database.Open(cfg)
	if err == nil || !strings.Contains(err.Error(), `column "operation_hash" nullability`) {
		t.Fatalf("database.Open() error = %v, want nullable operation rejection", err)
	}
}

func TestOpenRejectsInitializingSchemaWithUnexpectedFutureTable(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "forged-initializing.db"))
	forged, err := openUnversionedDatabase(cfg)
	if err != nil {
		t.Fatalf("open forged database: %v", err)
	}
	if err := autoMigrateTestModels(forged, &schemaMetadataTest{}, &model.Setting{}); err != nil {
		t.Fatalf("create forged initializing schema: %v", err)
	}
	if err := forged.Create(currentSchemaMetadataTest("initializing", 0, nil)).Error; err != nil {
		t.Fatalf("record forged initializing metadata: %v", err)
	}
	closeGormDB(t, forged)

	_, err = database.Open(cfg)
	if err == nil || !strings.Contains(err.Error(), "unexpected future") {
		t.Fatalf("database.Open() error = %v, want forged initializing rejection", err)
	}
}

func TestOpenRejectsReadySchemaWithMissingCurrentIndexesOrColumn(t *testing.T) {
	tests := []struct {
		name       string
		model      any
		index      string
		dropColumn string
	}{
		{name: "username unique", model: &model.User{}, index: "idx_users_username"},
		{name: "token digest unique", model: &model.AuthToken{}, index: "idx_auth_tokens_token_hash"},
		{name: "operation token unique", model: &model.AuthToken{}, index: "idx_auth_tokens_operation_hash"},
		{name: "resource owner composite", model: &model.Resource{}, index: "idx_resource_owner_key"},
		{name: "settings value", model: &model.Setting{}, dropColumn: "value"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "malformed-ready.db"))
			current, err := database.Open(cfg)
			if err != nil {
				t.Fatalf("create current database: %v", err)
			}
			if test.index != "" {
				err = current.Migrator().DropIndex(test.model, test.index)
			} else {
				err = current.Migrator().DropColumn(test.model, test.dropColumn)
			}
			if err != nil {
				t.Fatalf("malform current schema: %v", err)
			}
			closeGormDB(t, current)

			_, err = database.Open(cfg)
			if err == nil {
				t.Fatal("database.Open() error = nil, want strict current-shape rejection")
			}
			inspected, err := openUnversionedDatabase(cfg)
			if err != nil {
				t.Fatalf("reopen malformed database: %v", err)
			}
			defer closeGormDB(t, inspected)
			if test.index != "" && inspected.Migrator().HasIndex(test.model, test.index) {
				t.Fatalf("database.Open() recreated rejected index %q", test.index)
			}
			if test.dropColumn != "" && inspected.Migrator().HasColumn(test.model, test.dropColumn) {
				t.Fatalf("database.Open() recreated rejected column %q", test.dropColumn)
			}
		})
	}
}

func TestOpenRejectsReadySchemaWithWrongStorageTypeOrAutoIncrement(t *testing.T) {
	tests := []string{"storage type", "auto increment"}
	for _, mutation := range tests {
		t.Run(mutation, func(t *testing.T) {
			cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "wrong-storage.db"))
			current, err := database.Open(cfg)
			if err != nil {
				t.Fatalf("create current database: %v", err)
			}
			switch current.Dialector.Name() + "/" + mutation {
			case "sqlite/storage type":
				err = current.Exec("ALTER TABLE settings RENAME TO settings_current_backup").Error
				if err == nil {
					err = current.Exec("CREATE TABLE settings (key text PRIMARY KEY, value integer NOT NULL, created_at datetime NOT NULL, updated_at datetime NOT NULL)").Error
				}
				if err == nil {
					err = current.Exec("DROP TABLE settings_current_backup").Error
				}
			case "sqlite/auto increment":
				err = current.Exec("ALTER TABLE schema_metadata RENAME TO schema_metadata_current_backup").Error
				if err == nil {
					err = current.Exec("CREATE TABLE schema_metadata (id integer PRIMARY KEY AUTOINCREMENT, format_version integer NOT NULL, schema_version integer NOT NULL, contract_id text NOT NULL, state text NOT NULL, next_table integer NOT NULL, initialized_at datetime NOT NULL, ready_at datetime)").Error
				}
				if err == nil {
					err = current.Exec("INSERT INTO schema_metadata SELECT * FROM schema_metadata_current_backup").Error
				}
				if err == nil {
					err = current.Exec("DROP TABLE schema_metadata_current_backup").Error
				}
			case "mysql/storage type":
				err = current.Exec("ALTER TABLE settings MODIFY value BIGINT NOT NULL").Error
			case "mysql/auto increment":
				err = current.Exec("ALTER TABLE schema_metadata MODIFY id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT").Error
			default:
				t.Fatalf("unsupported test dialect %q", current.Dialector.Name())
			}
			if err != nil {
				t.Fatalf("malform current storage: %v", err)
			}
			closeGormDB(t, current)

			_, err = database.Open(cfg)
			if err == nil {
				t.Fatal("database.Open() error = nil, want storage fingerprint rejection")
			}
		})
	}
}

func TestOpenRejectsMySQLCurrentSchemaWithWrongIdentityCapacity(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "wrong-capacity.db"))
	if cfg.DatabaseDriver != "mysql" {
		t.Skip("SQLite stores logical string capacities in the current contract fingerprint")
	}
	current, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("create current database: %v", err)
	}
	if err := current.Exec("ALTER TABLE users MODIFY username VARCHAR(190) NOT NULL").Error; err != nil {
		t.Fatalf("malform current username capacity: %v", err)
	}
	closeGormDB(t, current)
	if _, err := database.Open(cfg); err == nil {
		t.Fatal("database.Open() error = nil, want capacity fingerprint rejection")
	}
}

func TestOpenRejectsMySQLCurrentSchemaWithWrongIntegerWidthOrSignedness(t *testing.T) {
	tests := []struct {
		name string
		sql  string
	}{
		{name: "resource revision width", sql: "ALTER TABLE resources MODIFY revision INT NOT NULL"},
		{name: "metadata signedness", sql: "ALTER TABLE schema_metadata MODIFY schema_version BIGINT NOT NULL"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "wrong-integer.db"))
			if cfg.DatabaseDriver != "mysql" {
				t.Skip("MySQL concrete integer contract")
			}
			current, err := database.Open(cfg)
			if err != nil {
				t.Fatalf("create current database: %v", err)
			}
			if err := current.Exec(test.sql).Error; err != nil {
				t.Fatalf("malform current integer storage: %v", err)
			}
			closeGormDB(t, current)
			if _, err := database.Open(cfg); err == nil {
				t.Fatal("database.Open() error = nil, want concrete integer rejection")
			}
		})
	}
}

func TestOpenRejectsMySQLPrefixUniqueIndexWithoutMutatingIt(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "prefix-index.db"))
	if cfg.DatabaseDriver != "mysql" {
		t.Skip("MySQL prefix-index contract")
	}
	current, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("create current database: %v", err)
	}
	if err := current.Exec("DROP INDEX idx_users_username ON users").Error; err != nil {
		t.Fatalf("drop current username index: %v", err)
	}
	if err := current.Exec("CREATE UNIQUE INDEX idx_users_username ON users (username(1))").Error; err != nil {
		t.Fatalf("create deceptive prefix index: %v", err)
	}
	closeGormDB(t, current)

	if _, err := database.Open(cfg); err == nil || !strings.Contains(err.Error(), "prefix length") {
		t.Fatalf("database.Open() error = %v, want prefix-index rejection", err)
	}
	inspected, err := openUnversionedDatabase(cfg)
	if err != nil {
		t.Fatalf("reopen rejected database: %v", err)
	}
	defer closeGormDB(t, inspected)
	var prefix sql.NullInt64
	if err := inspected.Raw(
		`SELECT SUB_PART FROM information_schema.STATISTICS
		  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?`,
		"users",
		"idx_users_username",
	).Scan(&prefix).Error; err != nil {
		t.Fatalf("inspect rejected prefix index: %v", err)
	}
	if !prefix.Valid || prefix.Int64 != 1 {
		t.Fatalf("rejected prefix index SUB_PART = %v, want 1", prefix)
	}
}

func TestOpenRejectsMySQLWrongEngineOrCollationWithoutMutatingIt(t *testing.T) {
	tests := []struct {
		name      string
		statement string
		wantError string
		query     string
		wantValue string
	}{
		{
			name:      "table engine",
			statement: "ALTER TABLE settings ENGINE=MyISAM",
			wantError: "table engine",
			query:     "SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'settings'",
			wantValue: "MyISAM",
		},
		{
			name:      "table collation",
			statement: "ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci",
			wantError: "table collation",
			query:     "SELECT TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users'",
			wantValue: "utf8mb4_general_ci",
		},
		{
			name:      "column collation",
			statement: "ALTER TABLE users MODIFY username VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL",
			wantError: "collation",
			query:     "SELECT COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'username'",
			wantValue: "utf8mb4_general_ci",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "wrong-table-storage.db"))
			if cfg.DatabaseDriver != "mysql" {
				t.Skip("MySQL table storage contract")
			}
			current, err := database.Open(cfg)
			if err != nil {
				t.Fatalf("create current database: %v", err)
			}
			if err := current.Exec(test.statement).Error; err != nil {
				t.Fatalf("malform current table storage: %v", err)
			}
			closeGormDB(t, current)

			if _, err := database.Open(cfg); err == nil || !strings.Contains(err.Error(), test.wantError) {
				t.Fatalf("database.Open() error = %v, want %q rejection", err, test.wantError)
			}
			inspected, err := openUnversionedDatabase(cfg)
			if err != nil {
				t.Fatalf("reopen rejected database: %v", err)
			}
			defer closeGormDB(t, inspected)
			var value string
			if err := inspected.Raw(test.query).Scan(&value).Error; err != nil {
				t.Fatalf("inspect rejected table storage: %v", err)
			}
			if !strings.EqualFold(value, test.wantValue) {
				t.Fatalf("rejected table storage = %q, want preserved %q", value, test.wantValue)
			}
		})
	}
}

func TestOpenRejectsSQLiteDeceptiveIndexesWithoutMutatingThem(t *testing.T) {
	tests := []struct {
		name      string
		statement string
		wantError string
		wantSQL   string
	}{
		{
			name:      "partial",
			statement: "CREATE UNIQUE INDEX idx_users_username ON users (username) WHERE username <> 'excluded'",
			wantError: "partial index",
			wantSQL:   "WHERE username <> 'excluded'",
		},
		{
			name:      "expression",
			statement: "CREATE UNIQUE INDEX idx_users_username ON users (lower(username))",
			wantError: "column 1",
			wantSQL:   "lower(username)",
		},
		{
			name:      "descending",
			statement: "CREATE UNIQUE INDEX idx_users_username ON users (username DESC)",
			wantError: "descending order",
			wantSQL:   "username DESC",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "deceptive-index.db"))
			if cfg.DatabaseDriver != "sqlite" {
				t.Skip("SQLite exact-index contract")
			}
			current, err := database.Open(cfg)
			if err != nil {
				t.Fatalf("create current database: %v", err)
			}
			if err := current.Exec("DROP INDEX idx_users_username").Error; err != nil {
				t.Fatalf("drop current username index: %v", err)
			}
			if err := current.Exec(test.statement).Error; err != nil {
				t.Fatalf("create deceptive index: %v", err)
			}
			closeGormDB(t, current)

			if _, err := database.Open(cfg); err == nil || !strings.Contains(err.Error(), test.wantError) {
				t.Fatalf("database.Open() error = %v, want %q rejection", err, test.wantError)
			}
			inspected, err := openUnversionedDatabase(cfg)
			if err != nil {
				t.Fatalf("reopen rejected database: %v", err)
			}
			defer closeGormDB(t, inspected)
			var definition string
			if err := inspected.Raw(
				"SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
				"idx_users_username",
			).Scan(&definition).Error; err != nil {
				t.Fatalf("inspect rejected deceptive index: %v", err)
			}
			if !strings.Contains(definition, test.wantSQL) {
				t.Fatalf("rejected index definition = %q, want preserved %q", definition, test.wantSQL)
			}
		})
	}
}

func TestOpenRejectsExtraCheckOrTriggerWithoutMutatingIt(t *testing.T) {
	tests := []string{"check", "trigger"}
	for _, mutation := range tests {
		t.Run(mutation, func(t *testing.T) {
			cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "extra-structure.db"))
			current, err := database.Open(cfg)
			if err != nil {
				t.Fatalf("create current database: %v", err)
			}
			switch current.Dialector.Name() + "/" + mutation {
			case "sqlite/check":
				err = current.Exec("ALTER TABLE settings RENAME TO settings_current_backup").Error
				if err == nil {
					err = current.Exec("CREATE TABLE settings (key text PRIMARY KEY, value text NOT NULL CHECK(length(value) > 0), created_at datetime NOT NULL, updated_at datetime NOT NULL)").Error
				}
				if err == nil {
					err = current.Exec("INSERT INTO settings SELECT * FROM settings_current_backup").Error
				}
				if err == nil {
					err = current.Exec("DROP TABLE settings_current_backup").Error
				}
			case "sqlite/trigger":
				err = current.Exec("CREATE TRIGGER reject_settings_insert BEFORE INSERT ON settings BEGIN SELECT RAISE(ABORT, 'blocked'); END").Error
			case "mysql/check":
				err = current.Exec("ALTER TABLE settings ADD CONSTRAINT chk_settings_value CHECK (CHAR_LENGTH(value) > 0)").Error
			case "mysql/trigger":
				err = current.Exec("CREATE TRIGGER rewrite_settings BEFORE INSERT ON settings FOR EACH ROW SET NEW.value = NEW.value").Error
			default:
				t.Fatalf("unsupported test dialect %q", current.Dialector.Name())
			}
			if err != nil {
				t.Fatalf("add deceptive %s: %v", mutation, err)
			}
			closeGormDB(t, current)

			if _, err := database.Open(cfg); err == nil || !strings.Contains(strings.ToLower(err.Error()), mutation) {
				t.Fatalf("database.Open() error = %v, want extra-%s rejection", err, mutation)
			}
			inspected, err := openUnversionedDatabase(cfg)
			if err != nil {
				t.Fatalf("reopen rejected database: %v", err)
			}
			defer closeGormDB(t, inspected)
			var count int64
			if inspected.Dialector.Name() == "sqlite" {
				if mutation == "check" {
					var definition string
					err = inspected.Raw("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'settings'").Scan(&definition).Error
					if strings.Contains(strings.ToUpper(definition), "CHECK") {
						count = 1
					}
				} else {
					err = inspected.Raw("SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'settings'").Scan(&count).Error
				}
			} else if mutation == "check" {
				err = inspected.Raw("SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'settings' AND CONSTRAINT_TYPE = 'CHECK'").Scan(&count).Error
			} else {
				err = inspected.Raw("SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE() AND EVENT_OBJECT_TABLE = 'settings'").Scan(&count).Error
			}
			if err != nil {
				t.Fatalf("inspect rejected %s: %v", mutation, err)
			}
			if count != 1 {
				t.Fatalf("rejected %s count = %d, want preserved 1", mutation, count)
			}
		})
	}
}

func TestOpenRejectsSchemaFromANewerBackend(t *testing.T) {
	cfg := testDatabaseConfiguration(t, filepath.Join(t.TempDir(), "future.db"))
	current, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("create current database: %v", err)
	}
	if err := current.Table("schema_metadata").Where("id = ?", 1).Update(
		"schema_version",
		database.CurrentSchemaVersion+1,
	).Error; err != nil {
		t.Fatalf("set future schema version: %v", err)
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
	if err := verified.Table("schema_metadata").Order("schema_version").Pluck("schema_version", &versions).Error; err != nil {
		t.Fatalf("read concurrent schema metadata: %v", err)
	}
	if !equalVersions(versions, []uint{database.CurrentSchemaVersion}) {
		t.Fatalf("concurrent schema versions = %v, want [%d]", versions, database.CurrentSchemaVersion)
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

func assertOperationHashNotNullable(t *testing.T, db *gorm.DB) {
	t.Helper()
	columns, err := db.Migrator().ColumnTypes(&model.AuthToken{})
	if err != nil {
		t.Fatalf("inspect auth token columns: %v", err)
	}
	for _, column := range columns {
		if strings.EqualFold(column.Name(), "operation_hash") {
			nullable, known := column.Nullable()
			if !known || nullable {
				t.Fatalf("auth_tokens.operation_hash nullable = %v, known = %v", nullable, known)
			}
			return
		}
	}
	t.Fatal("auth_tokens.operation_hash is missing")
}

type schemaMetadataTest struct {
	ID            uint      `gorm:"primaryKey;autoIncrement:false"`
	FormatVersion uint      `gorm:"not null"`
	SchemaVersion uint      `gorm:"not null"`
	ContractID    string    `gorm:"size:64;not null"`
	State         string    `gorm:"size:16;not null"`
	NextTable     uint      `gorm:"not null"`
	InitializedAt time.Time `gorm:"not null"`
	ReadyAt       *time.Time
}

func (schemaMetadataTest) TableName() string { return "schema_metadata" }

func currentSchemaMetadataTest(state string, nextTable uint, readyAt *time.Time) *schemaMetadataTest {
	return &schemaMetadataTest{
		ID:            1,
		FormatVersion: 1,
		SchemaVersion: database.CurrentSchemaVersion,
		ContractID:    database.CurrentSchemaContractID(),
		State:         state,
		NextTable:     nextTable,
		InitializedAt: time.Now().UTC(),
		ReadyAt:       readyAt,
	}
}

type nullableAuthTokenTest struct {
	ID            string    `gorm:"primaryKey;size:36"`
	UserID        string    `gorm:"index;size:36;not null"`
	TokenHash     string    `gorm:"uniqueIndex;size:64;not null"`
	OperationHash *string   `gorm:"uniqueIndex;size:64"`
	ExpiresAt     time.Time `gorm:"index;not null"`
	CreatedAt     time.Time `gorm:"not null"`
}

func (nullableAuthTokenTest) TableName() string { return "auth_tokens" }

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

func autoMigrateTestModels(db *gorm.DB, models ...any) error {
	if db.Dialector.Name() == "mysql" {
		db = db.Set("gorm:table_options", "ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin")
	}
	return db.AutoMigrate(models...)
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
