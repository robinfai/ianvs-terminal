package auth

import (
	"context"
	"errors"
	"ianvs-terminal/backend/internal/model"
	"testing"
	"time"
)

func TestSessionCapacityRecoveryRequiresConsentAndPassword(t *testing.T) {
	s, db := operationContractService(t)
	createOperationContractUser(t, db, "session-recovery")
	ctx := context.Background()
	var issued []Session
	for i := 0; i < 8; i++ {
		p, err := s.BeginLogin(ctx, "session-recovery", operationContractPassword)
		if err != nil {
			t.Fatal(err)
		}
		token, err := s.CompleteLogin(ctx, p.OperationID)
		if err != nil {
			t.Fatal(err)
		}
		issued = append(issued, token)
	}
	if _, err := s.BeginLogin(ctx, "session-recovery", operationContractPassword); !errors.Is(err, ErrSessionCapacity) {
		t.Fatalf("want capacity: %v", err)
	}
	if _, err := s.BeginLoginReplacingOldest(ctx, "session-recovery", "wrong-password", true); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("want invalid credentials: %v", err)
	}
	for _, token := range issued {
		if _, err := s.AuthenticateToken(ctx, token.Token); err != nil {
			t.Fatal("existing session changed", err)
		}
	}
	p, err := s.BeginLoginReplacingOldest(ctx, "session-recovery", operationContractPassword, true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.AuthenticateToken(ctx, issued[0].Token); err == nil {
		t.Fatal("oldest still valid")
	}
	for _, token := range issued[1:] {
		if _, err := s.AuthenticateToken(ctx, token.Token); err != nil {
			t.Fatal(err)
		}
	}
	token, err := s.CompleteLogin(ctx, p.OperationID)
	if err != nil {
		t.Fatal(err)
	}
	user, err := s.AuthenticateToken(ctx, token.Token)
	if err != nil {
		t.Fatal(err)
	}
	views, err := s.ListSessions(ctx, user.ID, token.Token)
	if err != nil || len(views) != 8 {
		t.Fatalf("list: %v %v", views, err)
	}
	current := 0
	for _, v := range views {
		if v.Current {
			current++
		}
	}
	if current != 1 {
		t.Fatalf("current markers: %d", current)
	}
	createOperationContractUser(t, db, "another-session-user")
	var other model.User
	db.Where("username = ?", "another-session-user").First(&other)
	if err := s.RevokeSession(ctx, other.ID, views[0].ID); err != nil {
		t.Fatal(err)
	}
	views2, _ := s.ListSessions(ctx, user.ID, token.Token)
	if len(views2) != 8 {
		t.Fatal("cross-user revoke")
	}
	var selected string
	for _, v := range views {
		if !v.Current {
			selected = v.ID
			break
		}
	}
	for i := 0; i < 2; i++ {
		if err := s.RevokeSession(ctx, user.ID, selected); err != nil {
			t.Fatal(err)
		}
	}
	views2, _ = s.ListSessions(ctx, user.ID, token.Token)
	if len(views2) != 7 {
		t.Fatal("revoke did not free slot")
	}
	if _, err := s.BeginLogin(ctx, "session-recovery", operationContractPassword); err != nil {
		t.Fatal(err)
	}
}

func TestRecoveryBelowCapacityPreservesSessionsAndHandlesPreparedSlot(t *testing.T) {
	s, db := operationContractService(t)
	createOperationContractUser(t, db, "prepared-recovery")
	ctx := context.Background()
	p, err := s.BeginLogin(ctx, "prepared-recovery", operationContractPassword)
	if err != nil {
		t.Fatal(err)
	}
	// Make this pending operation deterministically oldest.
	db.Model(&model.AuthOperation{}).Where("operation_hash = ?", hashOperationID(p.OperationID)).Update("created_at", time.Now().UTC().Add(-time.Minute))
	for i := 0; i < 7; i++ {
		if _, err := s.BeginLoginReplacingOldest(ctx, "prepared-recovery", operationContractPassword, true); err != nil {
			t.Fatal(err)
		}
	}
	assertOperationState(t, db, p.OperationID, authOperationStatePrepared)
	if _, err := s.BeginLoginReplacingOldest(ctx, "prepared-recovery", operationContractPassword, true); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteLogin(ctx, p.OperationID); !errors.Is(err, ErrOperationCanceled) {
		t.Fatalf("old pending login usable: %v", err)
	}
}

func TestDeviceNamePersistsAcrossServiceRestartAndCleansUp(t *testing.T) {
	s, db := operationContractService(t)
	createOperationContractUser(t, db, "named-device")
	ctx := context.Background()
	p, err := s.BeginLogin(ctx, "named-device", operationContractPassword)
	if err != nil {
		t.Fatal(err)
	}
	token, err := s.CompleteLogin(WithDeviceName(ctx, "Work MacBook\n · Chrome"), p.OperationID)
	if err != nil {
		t.Fatal(err)
	}
	restarted := New(db, time.Hour)
	user, err := restarted.AuthenticateToken(ctx, token.Token)
	if err != nil {
		t.Fatal(err)
	}
	views, err := restarted.ListSessions(ctx, user.ID, token.Token)
	if err != nil || len(views) != 1 || views[0].DeviceName != "Work MacBook · Chrome" {
		t.Fatalf("labels: %+v, %v", views, err)
	}
	if err := restarted.Logout(ctx, token.Token); err != nil {
		t.Fatal(err)
	}
	var count int64
	db.Model(&model.Setting{}).Where("key = ?", sessionMetadataKey(hashOperationID(p.OperationID))).Count(&count)
	if count != 0 {
		t.Fatal("device label survived logout")
	}
}
