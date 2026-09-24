package auth

import (
	"reflect"
	"strings"
	"testing"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/model"
)

// Exercise the MySQL dialect without requiring a running server, so SQLite
// development runs also catch reserved identifiers in session metadata SQL.
func TestSessionMetadataQueriesQuoteMySQLKey(t *testing.T) {
	db, err := gorm.Open(mysql.New(mysql.Config{
		DSN:                       "test@tcp(127.0.0.1:3306)/unused",
		SkipInitializeWithVersion: true,
	}), &gorm.Config{
		DryRun:                 true,
		DisableAutomaticPing:   true,
		SkipDefaultTransaction: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })

	for _, operation := range []string{"select", "delete"} {
		t.Run(operation, func(t *testing.T) {
			query := db.Where(sessionMetadataCondition("operation-hash"))
			var result *gorm.DB
			if operation == "select" {
				result = query.Limit(1).Find(&model.Setting{})
			} else {
				result = query.Delete(&model.Setting{})
			}
			if result.Error != nil {
				t.Fatal(result.Error)
			}
			if sql := result.Statement.SQL.String(); !strings.Contains(sql, "WHERE `key` = ?") {
				t.Fatalf("metadata predicate is not quoted and parameterized: %s", sql)
			}
			want := []interface{}{"auth.session.device/operation-hash"}
			if operation == "select" {
				want = append(want, 1)
			}
			if !reflect.DeepEqual(result.Statement.Vars, want) {
				t.Fatalf("bound values = %v, want %v", result.Statement.Vars, want)
			}
		})
	}
}
