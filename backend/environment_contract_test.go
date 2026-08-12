package backend_test

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

var forbiddenEnvironmentFunctions = map[string]bool{
	"Getenv":    true,
	"LookupEnv": true,
	"Environ":   true,
	"ExpandEnv": true,
}

func TestProductBackendDoesNotReadProcessEnvironment(t *testing.T) {
	var violations []string
	err := filepath.WalkDir(".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		clean := filepath.ToSlash(path)
		if entry.IsDir() {
			if clean == "internal/contracttest" {
				return filepath.SkipDir
			}
			return nil
		}
		if filepath.Ext(path) != ".go" || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		encoded, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, violation := range findEnvironmentAccess(path, encoded) {
			violations = append(violations, violation)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("scan backend product source: %v", err)
	}
	if len(violations) != 0 {
		t.Fatalf("backend product code reads the process environment:\n%s", strings.Join(violations, "\n"))
	}
}

func TestEnvironmentAccessScannerAdversarialImportsAndTearOffs(t *testing.T) {
	tests := []struct {
		name string
		src  string
		want int
	}{
		{
			name: "ordinary import",
			src:  `package fixture; import "os"; func f() { _ = os.Getenv("SECRET") }`,
			want: 1,
		},
		{
			name: "alias and tear off",
			src:  `package fixture; import system "os"; var lookup = system.LookupEnv`,
			want: 1,
		},
		{
			name: "dot import",
			src:  `package fixture; import . "os"; func f() { _ = Environ() }`,
			want: 1,
		},
		{
			name: "unrelated selector",
			src:  `package fixture; import "example.invalid/os"; func f() { _ = os.Getenv("safe") }`,
			want: 0,
		},
		{
			name: "same local name",
			src:  `package fixture; func Getenv(string) string { return "" }; func f() { _ = Getenv("safe") }`,
			want: 0,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got := findEnvironmentAccess("fixture.go", []byte(test.src))
			if len(got) != test.want {
				t.Fatalf("findEnvironmentAccess() = %v, want %d violation(s)", got, test.want)
			}
		})
	}
}

func findEnvironmentAccess(filename string, encoded []byte) []string {
	files := token.NewFileSet()
	parsed, err := parser.ParseFile(files, filename, encoded, 0)
	if err != nil {
		return []string{fmt.Sprintf("%s: parse source: %v", filename, err)}
	}
	osAliases := make(map[string]bool)
	dotOS := false
	for _, imported := range parsed.Imports {
		path, err := strconv.Unquote(imported.Path.Value)
		if err != nil || path != "os" {
			continue
		}
		switch {
		case imported.Name == nil:
			osAliases["os"] = true
		case imported.Name.Name == ".":
			dotOS = true
		case imported.Name.Name != "_":
			osAliases[imported.Name.Name] = true
		}
	}

	selectorNames := make(map[token.Pos]bool)
	ast.Inspect(parsed, func(node ast.Node) bool {
		if selector, ok := node.(*ast.SelectorExpr); ok {
			selectorNames[selector.Sel.Pos()] = true
		}
		return true
	})
	var violations []string
	ast.Inspect(parsed, func(node ast.Node) bool {
		switch expression := node.(type) {
		case *ast.SelectorExpr:
			qualifier, ok := expression.X.(*ast.Ident)
			if ok && osAliases[qualifier.Name] && forbiddenEnvironmentFunctions[expression.Sel.Name] {
				violations = append(violations, formatEnvironmentViolation(files, expression.Pos(), expression.Sel.Name))
			}
			return false
		case *ast.Ident:
			if dotOS && !selectorNames[expression.Pos()] && forbiddenEnvironmentFunctions[expression.Name] {
				violations = append(violations, formatEnvironmentViolation(files, expression.Pos(), expression.Name))
			}
		}
		return true
	})
	return violations
}

func formatEnvironmentViolation(files *token.FileSet, position token.Pos, function string) string {
	location := files.Position(position)
	return fmt.Sprintf("%s:%d: os.%s is forbidden outside tests", location.Filename, location.Line, function)
}
