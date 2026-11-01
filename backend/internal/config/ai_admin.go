package config

import (
	"errors"
	"path/filepath"
	"strings"
)

// Administrator membership is deployment-owned, never editable via user APIs.
type AIAdmin struct {
	UserIDs           []string `json:"user_ids"`
	EncryptionKeyFile string   `json:"encryption_key_file"`
}

func (c *AIAdmin) Validate(mode Mode) error {
	if c == nil {
		return nil
	}
	if mode != ModeRemote || len(c.UserIDs) == 0 || !filepath.IsAbs(c.EncryptionKeyFile) {
		return errors.New("ai_admin requires remote mode, administrator user IDs and an absolute encryption key file")
	}
	for _, id := range c.UserIDs {
		if len(id) != 36 || strings.TrimSpace(id) != id {
			return errors.New("invalid AI administrator user ID")
		}
	}
	return nil
}
