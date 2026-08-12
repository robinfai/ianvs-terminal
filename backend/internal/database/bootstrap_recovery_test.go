package database

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
)

func TestCurrentBootstrapRecoversEveryPersistedFailureBoundary(t *testing.T) {
	steps := []string{
		"after-metadata-table",
		"after-metadata-record",
	}
	for _, contract := range currentTableContracts {
		steps = append(steps, "after-create:"+contract.name)
	}
	for _, step := range steps {
		t.Run(step, func(t *testing.T) {
			cfg, cleanup, err := contracttest.NewDatabaseConfiguration(
				context.Background(),
				config.ModeLocal,
				filepath.Join(t.TempDir(), "bootstrap.db"),
			)
			if err != nil {
				t.Fatalf("create database contract configuration: %v", err)
			}
			t.Cleanup(func() {
				if err := cleanup(); err != nil {
					t.Errorf("clean up database contract: %v", err)
				}
			})

			injected := false
			bootstrapStepHook = func(observed string) error {
				if observed == step && !injected {
					injected = true
					return errors.New("injected bootstrap failure")
				}
				return nil
			}
			_, err = Open(cfg)
			bootstrapStepHook = nil
			t.Cleanup(func() { bootstrapStepHook = nil })
			if !injected || err == nil || !strings.Contains(err.Error(), "injected bootstrap failure") {
				t.Fatalf("Open() injected=%t error=%v", injected, err)
			}

			recovered, err := Open(cfg)
			if err != nil {
				t.Fatalf("Open() recovery error = %v", err)
			}
			defer func() {
				sqlDB, dbErr := recovered.DB()
				if dbErr == nil {
					_ = sqlDB.Close()
				}
			}()
			var metadata schemaMetadata
			if err := recovered.Where("id = ?", 1).First(&metadata).Error; err != nil {
				t.Fatalf("read recovered metadata: %v", err)
			}
			if metadata.State != schemaStateReady ||
				metadata.NextTable != uint(len(currentTableContracts)) ||
				metadata.ReadyAt == nil {
				t.Fatalf("recovered metadata = %#v", metadata)
			}
		})
	}
}
