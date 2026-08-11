package httpapi_test

import (
	"bufio"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"

	"ianvs-terminal/backend/internal/config"
)

type openAPIOperation struct {
	OperationID string
	Responses   map[string]struct{}
}

func TestOpenAPIPathsMatchImplementedHTTPRoutes(t *testing.T) {
	t.Parallel()

	operations := readOpenAPIOperations(t)
	wantOperationIDs := map[string]string{
		"GET /healthz":                     "health",
		"POST /v1/auth/setup":              "setupLocalUserKey",
		"POST /v1/auth/register":           "register",
		"POST /v1/auth/login":              "login",
		"POST /v1/auth/logout":             "logout",
		"POST /v1/auth/verify-key":         "verifyEncryptionKey",
		"GET /v1/me":                       "getCurrentUser",
		"GET /v1/resources":                "listResources",
		"GET /v1/resources/{kind}/{id}":    "getResource",
		"PUT /v1/resources/{kind}/{id}":    "putResource",
		"DELETE /v1/resources/{kind}/{id}": "deleteResource",
		"GET /v1/migrations/export":        "exportMigration",
		"POST /v1/migrations/merge":        "mergeMigration",
	}
	got := make(map[string]string, len(operations))
	operationIDs := make(map[string]string, len(operations))
	for route, operation := range operations {
		got[route] = operation.OperationID
		if operation.OperationID == "" {
			t.Errorf("%s has no operationId", route)
		}
		if previous, exists := operationIDs[operation.OperationID]; exists {
			t.Errorf("operationId %q is shared by %s and %s", operation.OperationID, previous, route)
		}
		operationIDs[operation.OperationID] = route
		if len(operation.Responses) == 0 {
			t.Errorf("%s documents no responses", route)
		}
	}
	implemented := readImplementedHTTPRoutes(t)
	if !reflect.DeepEqual(sortedRouteNames(got), implemented) {
		t.Fatalf("OpenAPI/implementation route mismatch\n documented: %v\nimplemented: %v", sortedRouteNames(got), implemented)
	}
	if !reflect.DeepEqual(got, wantOperationIDs) {
		t.Fatalf("OpenAPI operationId contract mismatch\n got: %v\nwant: %v", sortedRoutePairs(got), sortedRoutePairs(wantOperationIDs))
	}
}

func TestOpenAPIHealthContractMatchesSuccessAndFailureResponses(t *testing.T) {
	operations := readOpenAPIOperations(t)
	health := operations["GET /healthz"]
	for _, status := range []string{"200", "401", "403", "503"} {
		if _, exists := health.Responses[status]; !exists {
			t.Errorf("GET /healthz does not document status %s", status)
		}
	}

	_, db, handler := testAPI(t, config.ModeLocal)
	response := request(t, handler, http.MethodGet, "/healthz", nil, nil)
	if response.Code != http.StatusOK {
		t.Fatalf("healthy status = %d, body = %s", response.Code, response.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode health response: %v", err)
	}
	for _, field := range []string{"status", "mode", "server_id", "time"} {
		if _, exists := payload[field]; !exists {
			t.Errorf("health response is missing %q: %v", field, payload)
		}
	}

	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("obtain database pool: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close database pool: %v", err)
	}
	response = request(t, handler, http.MethodGet, "/healthz", nil, nil)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("unhealthy status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestOpenAPIVerifyKeyDocumentsEveryTypedRuntimeOutcome(t *testing.T) {
	operations := readOpenAPIOperations(t)
	verifyKey := operations["POST /v1/auth/verify-key"]
	for _, status := range []string{"200", "400", "401", "428", "429"} {
		if _, exists := verifyKey.Responses[status]; !exists {
			t.Errorf("POST /v1/auth/verify-key does not document status %s", status)
		}
	}
}

func readOpenAPIOperations(t *testing.T) map[string]openAPIOperation {
	t.Helper()
	path := filepath.Join("..", "..", "openapi.yaml")
	file, err := os.Open(path)
	if err != nil {
		t.Fatalf("open %s: %v", path, err)
	}
	defer file.Close()

	operations := map[string]openAPIOperation{}
	methods := map[string]struct{}{
		"get": {}, "post": {}, "put": {}, "patch": {}, "delete": {},
	}
	inPaths := false
	inResponses := false
	currentPath := ""
	currentMethod := ""
	currentRoute := ""
	scanner := bufio.NewScanner(file)
	for lineNumber := 1; scanner.Scan(); lineNumber++ {
		raw := scanner.Text()
		if strings.ContainsRune(raw, '\t') {
			t.Fatalf("%s:%d contains a tab", path, lineNumber)
		}
		if strings.TrimRight(raw, " ") != raw {
			t.Fatalf("%s:%d has trailing whitespace", path, lineNumber)
		}
		trimmed := strings.TrimSpace(raw)
		indent := len(raw) - len(strings.TrimLeft(raw, " "))
		if trimmed == "paths:" && indent == 0 {
			inPaths = true
			continue
		}
		if inPaths && indent == 0 && trimmed != "" {
			inPaths = false
		}
		if !inPaths {
			continue
		}
		if indent == 2 && strings.HasPrefix(trimmed, "/") && strings.HasSuffix(trimmed, ":") {
			currentPath = strings.TrimSuffix(trimmed, ":")
			currentMethod = ""
			currentRoute = ""
			inResponses = false
			continue
		}
		method := strings.TrimSuffix(trimmed, ":")
		if indent == 4 {
			if _, exists := methods[method]; exists {
				currentMethod = strings.ToUpper(method)
				currentRoute = currentMethod + " " + currentPath
				operations[currentRoute] = openAPIOperation{Responses: map[string]struct{}{}}
				inResponses = false
			}
			continue
		}
		if currentRoute == "" {
			continue
		}
		if indent == 6 && strings.HasPrefix(trimmed, "operationId:") {
			operation := operations[currentRoute]
			operation.OperationID = strings.TrimSpace(strings.TrimPrefix(trimmed, "operationId:"))
			operations[currentRoute] = operation
			continue
		}
		if indent == 6 && trimmed == "responses:" {
			inResponses = true
			continue
		}
		if inResponses && indent <= 6 && trimmed != "" {
			inResponses = false
		}
		if inResponses && indent == 8 && len(trimmed) >= 6 && trimmed[0] == '\'' && trimmed[4] == '\'' && trimmed[5] == ':' {
			operation := operations[currentRoute]
			operation.Responses[trimmed[1:4]] = struct{}{}
			operations[currentRoute] = operation
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("scan %s: %v", path, err)
	}
	return operations
}

func sortedRoutePairs(routes map[string]string) []string {
	pairs := make([]string, 0, len(routes))
	for route, operationID := range routes {
		pairs = append(pairs, route+"="+operationID)
	}
	sort.Strings(pairs)
	return pairs
}

func sortedRouteNames(routes map[string]string) []string {
	names := make([]string, 0, len(routes))
	for route := range routes {
		names = append(names, route)
	}
	sort.Strings(names)
	return names
}

func readImplementedHTTPRoutes(t *testing.T) []string {
	t.Helper()
	source, err := os.ReadFile("api.go")
	if err != nil {
		t.Fatalf("read api.go: %v", err)
	}
	matches := regexp.MustCompile(`a\.mux\.Handle(?:Func)?\("([A-Z]+ /[^" ]*)"`).FindAllSubmatch(source, -1)
	routes := make([]string, 0, len(matches))
	for _, match := range matches {
		routes = append(routes, string(match[1]))
	}
	sort.Strings(routes)
	return routes
}
