package auth

import (
	"errors"
	"testing"
)

func TestPasswordHashAdmissionRejectsWorkInsteadOfQueuingBeyondCapacity(t *testing.T) {
	admission := newPasswordHashAdmission(1)
	started := make(chan struct{})
	release := make(chan struct{})
	completed := make(chan error, 1)
	go func() {
		completed <- admission.run(func() error {
			close(started)
			<-release
			return nil
		})
	}()
	<-started

	if err := admission.run(func() error { return nil }); !errors.Is(err, ErrPasswordHashBusy) {
		t.Fatalf("run() error = %v, want ErrPasswordHashBusy", err)
	}
	close(release)
	if err := <-completed; err != nil {
		t.Fatalf("admitted run() error = %v", err)
	}
}

func TestGlobalPasswordHashAdmissionHasDocumentedCapacity(t *testing.T) {
	if got := cap(passwordHashAdmission.slots); got != maximumConcurrentPasswordHashes {
		t.Fatalf("global password hash capacity = %d, want %d", got, maximumConcurrentPasswordHashes)
	}
}
