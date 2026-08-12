package backend_test

import (
	"os"
	"strings"
	"testing"
)

func TestContainerCopiesHostSecretThenDropsPrivileges(t *testing.T) {
	dockerfile := readContractFile(t, "Dockerfile")
	entrypoint := readContractFile(t, "container-entrypoint.sh")
	compose := readContractFile(t, "compose.mysql.yaml")
	entrypointInfo, err := os.Stat("container-entrypoint.sh")
	if err != nil {
		t.Fatalf("stat container entrypoint: %v", err)
	}
	if entrypointInfo.Mode().Perm()&0o111 == 0 {
		t.Fatal("container entrypoint source is not executable")
	}

	for _, required := range []string{
		"apk add --no-cache ca-certificates su-exec tzdata",
		"COPY --chmod=0555 container-entrypoint.sh /usr/local/bin/ianvs-container-entrypoint",
		`ENTRYPOINT ["ianvs-container-entrypoint"]`,
		`CMD ["serve", "--config", "/run/secrets/ianvs-api-config.json"]`,
	} {
		if !strings.Contains(dockerfile, required) {
			t.Fatalf("Dockerfile omitted deployment contract %q", required)
		}
	}
	if strings.Contains(dockerfile, "USER ianvs") {
		t.Fatal("Dockerfile drops privileges before copying a host-owned 0400 secret")
	}
	for _, required := range []string{
		"install -d -m 0710 -o root -g ianvs",
		"install -m 0400 -o ianvs -g ianvs",
		"mv -f \"$temporary_config\" \"$private_config\"",
		"exec su-exec ianvs:ianvs /usr/local/bin/ianvs-api serve --config",
		"/run/ianvs-api",
	} {
		if !strings.Contains(entrypoint, required) {
			t.Fatalf("entrypoint omitted secret-copy contract %q", required)
		}
	}
	if strings.Contains(entrypoint, "install -d -m 0700 -o ianvs") {
		t.Fatal("unprivileged API user must not own the private configuration directory")
	}
	if strings.Contains(compose, "  api:\n    environment:") {
		t.Fatal("API container must not receive runtime configuration through environment")
	}
	if !strings.Contains(compose, ":/run/secrets/ianvs-api-config.json:ro") {
		t.Fatal("Compose must mount the host configuration read-only at the fixed source path")
	}
}

func readContractFile(t *testing.T, path string) string {
	t.Helper()
	encoded, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(encoded)
}
