package auth

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/identity"
	"ianvs-terminal/backend/internal/model"
)

const operationContractPassword = "operation-password"

func TestBeginLoginPreparesWithoutTokenThenCompleteIssues(t *testing.T) {
	service, db := operationContractService(t)
	createOperationContractUser(t, db, "prepared-login")

	prepared, err := service.BeginLogin(context.Background(), "prepared-login", operationContractPassword)
	if err != nil {
		t.Fatalf("BeginLogin() error = %v", err)
	}
	assertOperationState(t, db, prepared.OperationID, authOperationStatePrepared)
	assertOperationTokenCount(t, db, prepared.OperationID, 0)

	session, err := service.CompleteLogin(context.Background(), prepared.OperationID)
	if err != nil {
		t.Fatalf("CompleteLogin() error = %v", err)
	}
	assertOperationState(t, db, prepared.OperationID, authOperationStateIssued)
	assertOperationTokenCount(t, db, prepared.OperationID, 1)
	if _, err := service.AuthenticateToken(context.Background(), session.Token); err != nil {
		t.Fatalf("issued token was not usable: %v", err)
	}
}

func TestCancelPreparedOperationWinsBeforeDelayedCompleteAcrossInstances(t *testing.T) {
	service, canceler, db := operationContractServicePair(t)
	createOperationContractUser(t, db, "delayed-complete")
	prepared, err := service.BeginLogin(context.Background(), "delayed-complete", operationContractPassword)
	if err != nil {
		t.Fatalf("BeginLogin() error = %v", err)
	}
	started := make(chan struct{})
	release := make(chan struct{})
	service.beforeIssue = func() {
		close(started)
		<-release
	}
	result := make(chan error, 1)
	go func() {
		_, completeErr := service.CompleteLogin(context.Background(), prepared.OperationID)
		result <- completeErr
	}()
	waitForOperationBarrier(t, started, "CompleteLogin")
	if err := canceler.CancelOperation(context.Background(), prepared.OperationID); err != nil {
		t.Fatalf("CancelOperation() error = %v", err)
	}
	close(release)
	if err := <-result; !errors.Is(err, ErrOperationCanceled) {
		t.Fatalf("delayed CompleteLogin() error = %v, want ErrOperationCanceled", err)
	}
	assertOperationState(t, db, prepared.OperationID, authOperationStateCanceled)
	assertOperationTokenCount(t, db, prepared.OperationID, 0)
}

func TestCancelIssuedLostResponseRevokesTokenAndIsIdempotent(t *testing.T) {
	service, db := operationContractService(t)
	createOperationContractUser(t, db, "lost-response")
	prepared, err := service.BeginLogin(context.Background(), "lost-response", operationContractPassword)
	if err != nil {
		t.Fatalf("BeginLogin() error = %v", err)
	}
	session, err := service.CompleteLogin(context.Background(), prepared.OperationID)
	if err != nil {
		t.Fatalf("CompleteLogin() error = %v", err)
	}
	for attempt := 0; attempt < 2; attempt++ {
		if err := service.CancelOperation(context.Background(), prepared.OperationID); err != nil {
			t.Fatalf("CancelOperation() attempt %d error = %v", attempt+1, err)
		}
	}
	if _, err := service.AuthenticateToken(context.Background(), session.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("canceled token error = %v, want ErrInvalidCredentials", err)
	}
	assertOperationState(t, db, prepared.OperationID, authOperationStateCanceled)
	assertOperationTokenCount(t, db, prepared.OperationID, 0)
}

func TestRepeatedLoginAndLogoutReleasesOperationCapacity(t *testing.T) {
	service, db := operationContractService(t)
	createOperationContractUser(t, db, "logout-capacity")
	for attempt := 0; attempt < maximumActiveSessionsPerUser; attempt++ {
		prepared, err := service.BeginLogin(
			context.Background(),
			"logout-capacity",
			operationContractPassword,
		)
		if err != nil {
			t.Fatalf("BeginLogin() attempt %d error = %v", attempt+1, err)
		}
		session, err := service.CompleteLogin(context.Background(), prepared.OperationID)
		if err != nil {
			t.Fatalf("CompleteLogin() attempt %d error = %v", attempt+1, err)
		}
		if err := service.Logout(context.Background(), session.Token); err != nil {
			t.Fatalf("Logout() attempt %d error = %v", attempt+1, err)
		}
		assertOperationState(t, db, prepared.OperationID, authOperationStateCanceled)
	}
	if _, err := service.BeginLogin(
		context.Background(),
		"logout-capacity",
		operationContractPassword,
	); err != nil {
		t.Fatalf("BeginLogin() after %d logout cycles error = %v", maximumActiveSessionsPerUser, err)
	}
}

func TestConcurrentLogoutAcrossInstancesReleasesCapacityExactlyOnce(t *testing.T) {
	service, competitor, db := operationContractServicePair(t)
	user := createOperationContractUser(t, db, "concurrent-logout")
	now := time.Now().UTC()
	for index := 0; index < maximumActiveSessionsPerUser-1; index++ {
		operationID := operationContractID(t)
		if err := db.Create(&model.AuthOperation{
			OperationHash: hashOperationID(operationID),
			Kind:          authOperationKindLogin,
			State:         authOperationStatePrepared,
			UserID:        user.ID,
			ExpiresAt:     now.Add(time.Hour),
		}).Error; err != nil {
			t.Fatalf("seed prepared operation %d: %v", index, err)
		}
	}
	prepared, err := service.BeginLogin(
		context.Background(),
		"concurrent-logout",
		operationContractPassword,
	)
	if err != nil {
		t.Fatalf("BeginLogin() error = %v", err)
	}
	session, err := service.CompleteLogin(context.Background(), prepared.OperationID)
	if err != nil {
		t.Fatalf("CompleteLogin() error = %v", err)
	}

	start := make(chan struct{})
	results := make(chan error, 2)
	for _, logoutService := range []*Service{service, competitor} {
		go func() {
			<-start
			results <- logoutService.Logout(context.Background(), session.Token)
		}()
	}
	close(start)
	for range 2 {
		if err := <-results; err != nil {
			t.Fatalf("concurrent Logout() error = %v", err)
		}
	}
	assertOperationState(t, db, prepared.OperationID, authOperationStateCanceled)
	assertOperationTokenCount(t, db, prepared.OperationID, 0)
	if _, err := competitor.BeginLogin(
		context.Background(),
		"concurrent-logout",
		operationContractPassword,
	); err != nil {
		t.Fatalf("BeginLogin() after concurrent logout error = %v", err)
	}
}

func TestUnknownCancellationNeverCreatesAuthenticationRows(t *testing.T) {
	service, db := operationContractService(t)
	for attempt := 0; attempt < 128; attempt++ {
		if err := service.CancelOperation(context.Background(), operationContractID(t)); err != nil {
			t.Fatalf("unknown CancelOperation() attempt %d error = %v", attempt+1, err)
		}
	}
	var operationCount int64
	if err := db.Model(&model.AuthOperation{}).Count(&operationCount).Error; err != nil {
		t.Fatalf("count operations after unknown cancellation flood: %v", err)
	}
	if operationCount != 0 {
		t.Fatalf("unknown cancellation operation count = %d, want 0", operationCount)
	}
}

func TestConcurrentCompleteAcrossInstancesIssuesExactlyOneToken(t *testing.T) {
	service, competitor, db := operationContractServicePair(t)
	createOperationContractUser(t, db, "concurrent-complete")
	prepared, err := service.BeginLogin(context.Background(), "concurrent-complete", operationContractPassword)
	if err != nil {
		t.Fatalf("BeginLogin() error = %v", err)
	}
	start := make(chan struct{})
	results := make(chan error, 2)
	for _, issuer := range []*Service{service, competitor} {
		go func() {
			<-start
			_, completeErr := issuer.CompleteLogin(context.Background(), prepared.OperationID)
			results <- completeErr
		}()
	}
	close(start)
	issued := 0
	reused := 0
	for range 2 {
		err := <-results
		switch {
		case err == nil:
			issued++
		case errors.Is(err, ErrOperationReused):
			reused++
		default:
			t.Fatalf("concurrent CompleteLogin() error = %v", err)
		}
	}
	if issued != 1 || reused != 1 {
		t.Fatalf("concurrent completion outcomes: issued=%d reused=%d", issued, reused)
	}
	assertOperationTokenCount(t, db, prepared.OperationID, 1)
}

func TestRegisterBeginCreatesAccountWithoutTokenAndSupportsCancellation(t *testing.T) {
	service, db := operationContractService(t)
	prepared, err := service.BeginRegister(
		context.Background(),
		"prepared-register",
		operationContractPassword,
	)
	if err != nil {
		t.Fatalf("BeginRegister() error = %v", err)
	}
	assertUserCount(t, db, "prepared-register", 1)
	assertOperationState(t, db, prepared.OperationID, authOperationStatePrepared)
	assertOperationTokenCount(t, db, prepared.OperationID, 0)

	if err := service.CancelOperation(context.Background(), prepared.OperationID); err != nil {
		t.Fatalf("CancelOperation() error = %v", err)
	}
	if _, err := service.CompleteRegister(context.Background(), prepared.OperationID); !errors.Is(err, ErrOperationCanceled) {
		t.Fatalf("CompleteRegister() after cancellation error = %v, want ErrOperationCanceled", err)
	}
	assertUserCount(t, db, "prepared-register", 1)

	issued, err := service.BeginRegister(
		context.Background(),
		"issued-register",
		operationContractPassword,
	)
	if err != nil {
		t.Fatalf("second BeginRegister() error = %v", err)
	}
	session, err := service.CompleteRegister(context.Background(), issued.OperationID)
	if err != nil {
		t.Fatalf("CompleteRegister() error = %v", err)
	}
	if _, err := service.CompleteLogin(context.Background(), issued.OperationID); !errors.Is(err, ErrOperationKind) {
		t.Fatalf("wrong-kind completion error = %v, want ErrOperationKind", err)
	}
	if err := service.CancelOperation(context.Background(), issued.OperationID); err != nil {
		t.Fatalf("issued registration CancelOperation() error = %v", err)
	}
	if _, err := service.AuthenticateToken(context.Background(), session.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("canceled registration token error = %v, want ErrInvalidCredentials", err)
	}
	assertUserCount(t, db, "issued-register", 1)
}

func TestPerUserOperationQuotaIsExactAcrossInstances(t *testing.T) {
	service, competitor, db := operationContractServicePair(t)
	user := createOperationContractUser(t, db, "operation-quota")
	now := time.Now().UTC()
	for index := 0; index < maximumActiveSessionsPerUser-1; index++ {
		operationID := operationContractID(t)
		if err := db.Create(&model.AuthOperation{
			OperationHash: hashOperationID(operationID),
			Kind:          authOperationKindLogin,
			State:         authOperationStatePrepared,
			UserID:        user.ID,
			ExpiresAt:     now.Add(time.Hour),
		}).Error; err != nil {
			t.Fatalf("seed prepared operation %d: %v", index, err)
		}
	}
	start := make(chan struct{})
	results := make(chan error, 2)
	for _, issuer := range []*Service{service, competitor} {
		go func() {
			<-start
			_, beginErr := issuer.BeginLogin(context.Background(), "operation-quota", operationContractPassword)
			results <- beginErr
		}()
	}
	close(start)
	created := 0
	limited := 0
	for range 2 {
		err := <-results
		switch {
		case err == nil:
			created++
		case errors.Is(err, ErrSessionCapacity):
			limited++
		default:
			t.Fatalf("concurrent BeginLogin() error = %v", err)
		}
	}
	if created != 1 || limited != 1 {
		t.Fatalf("quota outcomes: created=%d limited=%d", created, limited)
	}
	var active int64
	if err := db.Model(&model.AuthOperation{}).
		Where("user_id = ? AND state = ?", user.ID, authOperationStatePrepared).
		Count(&active).Error; err != nil {
		t.Fatalf("count quota operations: %v", err)
	}
	if active != maximumActiveSessionsPerUser {
		t.Fatalf("active prepared operations = %d, want %d", active, maximumActiveSessionsPerUser)
	}
}

func TestExpiredPreparedOperationIsCollectedAndCannotComplete(t *testing.T) {
	service, db := operationContractService(t)
	createOperationContractUser(t, db, "operation-gc")
	prepared, err := service.BeginLogin(context.Background(), "operation-gc", operationContractPassword)
	if err != nil {
		t.Fatalf("BeginLogin() error = %v", err)
	}
	if err := db.Model(&model.AuthOperation{}).
		Where("operation_hash = ?", hashOperationID(prepared.OperationID)).
		Update("expires_at", time.Now().UTC().Add(-time.Hour)).Error; err != nil {
		t.Fatalf("expire prepared operation: %v", err)
	}
	if _, err := service.CompleteLogin(context.Background(), prepared.OperationID); !errors.Is(err, ErrOperationNotFound) {
		t.Fatalf("expired CompleteLogin() error = %v, want ErrOperationNotFound", err)
	}
	var count int64
	if err := db.Model(&model.AuthOperation{}).
		Where("operation_hash = ?", hashOperationID(prepared.OperationID)).
		Count(&count).Error; err != nil {
		t.Fatalf("count expired operation: %v", err)
	}
	if count != 0 {
		t.Fatalf("expired operation count = %d, want 0", count)
	}
}

func TestValidateOperationIDRequiresCanonical256BitCapability(t *testing.T) {
	if err := ValidateOperationID(operationContractID(t)); err != nil {
		t.Fatalf("valid operation ID rejected: %v", err)
	}
	for index, invalid := range []string{"", "short", "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!", operationContractID(t) + "="} {
		if err := ValidateOperationID(invalid); !errors.Is(err, ErrInvalidOperationID) {
			t.Fatalf("invalid operation ID case %d error = %v, want ErrInvalidOperationID", index, err)
		}
	}
}

func operationContractService(t *testing.T) (*Service, *gorm.DB) {
	t.Helper()
	cfg := operationContractConfiguration(t)
	db := openOperationContractDatabase(t, cfg)
	return New(db, time.Hour), db
}

func operationContractServicePair(t *testing.T) (*Service, *Service, *gorm.DB) {
	t.Helper()
	cfg := operationContractConfiguration(t)
	first := openOperationContractDatabase(t, cfg)
	second := openOperationContractDatabase(t, cfg)
	return New(first, time.Hour), New(second, time.Hour), first
}

func operationContractConfiguration(t *testing.T) config.Config {
	t.Helper()
	cfg, cleanup, err := contracttest.NewDatabaseConfiguration(
		context.Background(),
		config.ModeRemote,
		filepath.Join(t.TempDir(), "auth-operation.db"),
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

func openOperationContractDatabase(t *testing.T, cfg config.Config) *gorm.DB {
	t.Helper()
	db, err := database.Open(cfg)
	if err != nil {
		t.Fatalf("database.Open() error = %v", err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("database pool error = %v", err)
	}
	t.Cleanup(func() {
		if err := sqlDB.Close(); err != nil {
			t.Errorf("close database pool: %v", err)
		}
	})
	return db
}

func createOperationContractUser(t *testing.T, db *gorm.DB, username string) model.User {
	t.Helper()
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(operationContractPassword), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("hash operation contract password: %v", err)
	}
	userID, err := identity.UUID()
	if err != nil {
		t.Fatalf("generate operation contract user ID: %v", err)
	}
	user := model.User{ID: userID, Username: username, PasswordHash: string(passwordHash)}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("create operation contract user: %v", err)
	}
	return user
}

func operationContractID(t *testing.T) string {
	t.Helper()
	operationID, err := identity.Secret(32)
	if err != nil {
		t.Fatalf("generate operation ID: %v", err)
	}
	return operationID
}

func assertOperationState(t *testing.T, db *gorm.DB, operationID, expected string) {
	t.Helper()
	var operation model.AuthOperation
	if err := db.Where("operation_hash = ?", hashOperationID(operationID)).First(&operation).Error; err != nil {
		t.Fatalf("load operation: %v", err)
	}
	if operation.State != expected {
		t.Fatalf("operation state = %q, want %q", operation.State, expected)
	}
	if operation.OperationHash == operationID {
		t.Fatal("raw operation capability was persisted")
	}
}

func assertOperationTokenCount(t *testing.T, db *gorm.DB, operationID string, expected int64) {
	t.Helper()
	var count int64
	if err := db.Model(&model.AuthToken{}).
		Where("operation_hash = ?", hashOperationID(operationID)).
		Count(&count).Error; err != nil {
		t.Fatalf("count operation tokens: %v", err)
	}
	if count != expected {
		t.Fatalf("operation token count = %d, want %d", count, expected)
	}
}

func assertUserCount(t *testing.T, db *gorm.DB, username string, expected int64) {
	t.Helper()
	var count int64
	if err := db.Model(&model.User{}).Where("username = ?", username).Count(&count).Error; err != nil {
		t.Fatalf("count user %q: %v", username, err)
	}
	if count != expected {
		t.Fatalf("user %q count = %d, want %d", username, count, expected)
	}
}

func waitForOperationBarrier(t *testing.T, started <-chan struct{}, operation string) {
	t.Helper()
	select {
	case <-started:
	case <-time.After(10 * time.Second):
		t.Fatalf("timed out waiting for delayed %s operation", operation)
	}
}
