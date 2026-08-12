package model

import "time"

// User owns every persisted resource. Local mode creates one reserved user;
// remote mode creates one row for each registered account.
type User struct {
	ID            string    `gorm:"primaryKey;size:36"`
	Username      string    `gorm:"uniqueIndex;size:191;not null"`
	PasswordHash  string    `gorm:"size:255"`
	KeyDerivation string    `gorm:"size:64"`
	KeySalt       string    `gorm:"size:255"`
	KeyVerifier   string    `gorm:"size:255"`
	CreatedAt     time.Time `gorm:"not null"`
	UpdatedAt     time.Time `gorm:"not null"`
}

func (User) TableName() string { return "users" }

// AuthToken stores only a digest of the bearer token returned to a remote
// client. Tokens are intentionally independent from the user's encryption key.
type AuthToken struct {
	ID            string    `gorm:"primaryKey;size:36"`
	UserID        string    `gorm:"index;size:36;not null"`
	TokenHash     string    `gorm:"uniqueIndex;size:64;not null"`
	OperationHash string    `gorm:"uniqueIndex;size:64;not null"`
	ExpiresAt     time.Time `gorm:"index;not null"`
	CreatedAt     time.Time `gorm:"not null"`
}

func (AuthToken) TableName() string { return "auth_tokens" }

// AuthOperation stores the digest of a server-issued cancellation capability.
// It never stores the raw operation ID, bearer token, password, or encryption
// key. A client must durably record a prepared capability before completing
// the operation that atomically creates its token.
type AuthOperation struct {
	OperationHash string    `gorm:"primaryKey;size:64"`
	Kind          string    `gorm:"size:16;not null"`
	State         string    `gorm:"size:16;not null"`
	UserID        string    `gorm:"index;size:36"`
	ExpiresAt     time.Time `gorm:"index;not null"`
	CreatedAt     time.Time `gorm:"not null"`
	UpdatedAt     time.Time `gorm:"not null"`
}

func (AuthOperation) TableName() string { return "auth_operations" }

// Resource is the database-neutral persistence unit shared by profiles,
// terminal relaunch sessions, and named configuration documents. JSON is kept
// in text columns instead of dialect-specific JSON columns so SQLite and MySQL
// use the same model and query paths.
type Resource struct {
	ID                  string     `gorm:"primaryKey;size:36"`
	UserID              string     `gorm:"uniqueIndex:idx_resource_owner_key;index;size:36;not null"`
	Kind                string     `gorm:"uniqueIndex:idx_resource_owner_key;index;size:64;not null"`
	ExternalID          string     `gorm:"uniqueIndex:idx_resource_owner_key;size:191;not null"`
	PlainJSON           string     `gorm:"size:4194304;not null"`
	SensitiveCiphertext string     `gorm:"size:6291456"`
	SensitiveFormat     string     `gorm:"size:64"`
	Revision            int64      `gorm:"not null"`
	SourceID            string     `gorm:"size:64"`
	SourceRevision      int64      `gorm:"not null"`
	OriginUpdatedAt     time.Time  `gorm:"index;not null"`
	Deleted             bool       `gorm:"index;not null"`
	DeletedAt           *time.Time `gorm:"index"`
	CreatedAt           time.Time  `gorm:"not null"`
	UpdatedAt           time.Time  `gorm:"not null"`
}

func (Resource) TableName() string { return "resources" }

// Setting holds server-scoped metadata such as the stable source identifier
// included in migration bundles.
type Setting struct {
	Key       string    `gorm:"primaryKey;size:191"`
	Value     string    `gorm:"size:4194304;not null"`
	CreatedAt time.Time `gorm:"not null"`
	UpdatedAt time.Time `gorm:"not null"`
}

func (Setting) TableName() string { return "settings" }
