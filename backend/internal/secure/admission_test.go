package secure

import (
	"errors"
	"testing"
)

func TestDerivationAdmissionRejectsWorkInsteadOfQueuingBeyondCapacity(t *testing.T) {
	admission := newDerivationAdmission(1)
	started := make(chan struct{})
	release := make(chan struct{})
	completed := make(chan error, 1)
	go func() {
		_, err := admission.run(func() []byte {
			close(started)
			<-release
			return []byte{1}
		})
		completed <- err
	}()
	<-started

	if _, err := admission.run(func() []byte { return []byte{2} }); !errors.Is(err, ErrKeyDerivationBusy) {
		t.Fatalf("run() error = %v, want ErrKeyDerivationBusy", err)
	}
	close(release)
	if err := <-completed; err != nil {
		t.Fatalf("admitted run() error = %v", err)
	}
}

func TestGlobalDerivationAdmissionHasDocumentedCapacity(t *testing.T) {
	if got := cap(keyDerivationAdmission.slots); got != maximumConcurrentKeyDerivations {
		t.Fatalf("global derivation capacity = %d, want %d", got, maximumConcurrentKeyDerivations)
	}
}
