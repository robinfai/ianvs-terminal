package main

import (
	"strings"
	"testing"
)

func TestRunRequiresExplicitCurrentCommandShape(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want string
	}{
		{name: "command", want: "command is required"},
		{name: "config", args: []string{"serve"}, want: "exactly --config <path>"},
		{name: "config value", args: []string{"serve", "--config"}, want: "exactly --config <path>"},
		{name: "duplicate config", args: []string{"serve", "--config", "one", "--config", "two"}, want: "exactly --config <path>"},
		{name: "removed import", args: []string{"import-legacy"}, want: "unknown command"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			err := run(test.args)
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("run(%q) error = %v, want %q", test.args, err, test.want)
			}
		})
	}
}

func TestRunAcceptsOnlyAPathArgumentBeforeLoadingConfiguration(t *testing.T) {
	err := run([]string{"serve", "--config", t.TempDir() + "/missing.json"})
	if err == nil || !strings.Contains(err.Error(), "open configuration") {
		t.Fatalf("run() error = %v, want configuration load attempt", err)
	}
}
