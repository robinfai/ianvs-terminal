package store_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gorm.io/gorm"

	"ianvs-terminal/backend/internal/config"
	"ianvs-terminal/backend/internal/contracttest"
	"ianvs-terminal/backend/internal/database"
	"ianvs-terminal/backend/internal/identity"
	"ianvs-terminal/backend/internal/model"
	"ianvs-terminal/backend/internal/store"
)

func TestOpaqueSensitivePayloadAndOptimisticRevision(t *testing.T) {
	ctx := context.Background()
	db, resourceStore := testStore(t)
	user, _ := testUser(t, db, "alice", "alice-encryption-key-material")

	created, err := resourceStore.Put(ctx, user, "profile", "work", store.WriteInput{
		Data:             json.RawMessage(`{"name":"Work","connection":{"host":"example.com"}}`),
		Sensitive:        json.RawMessage(`{"connection":{"password":"server-secret"}}`),
		SensitivePresent: true,
	})
	if err != nil {
		t.Fatalf("Put() error = %v", err)
	}
	if created.Revision != 1 || string(created.Sensitive) != `{"connection":{"password":"server-secret"}}` {
		t.Fatalf("Put() = %#v", created)
	}

	var persisted model.Resource
	if err := db.Where("user_id = ? AND kind = ? AND external_id = ?", user.ID, "profile", "work").First(&persisted).Error; err != nil {
		t.Fatalf("load persisted resource: %v", err)
	}
	if strings.Contains(persisted.PlainJSON, "server-secret") || !strings.Contains(persisted.SensitiveJSON, "server-secret") {
		t.Fatal("server did not keep the sensitive payload isolated as opaque JSON")
	}

	withoutSecret, err := resourceStore.Get(ctx, user, "profile", "work", false)
	if err != nil {
		t.Fatalf("Get(without sensitive) error = %v", err)
	}
	if withoutSecret.Sensitive != nil || !withoutSecret.HasSensitive {
		t.Fatalf("Get(without sensitive) = %#v", withoutSecret)
	}
	withSecret, err := resourceStore.Get(ctx, user, "profile", "work", true)
	if err != nil {
		t.Fatalf("Get(with sensitive) error = %v", err)
	}
	if string(withSecret.Sensitive) != `{"connection":{"password":"server-secret"}}` {
		t.Fatalf("Get().Sensitive = %s", withSecret.Sensitive)
	}

	stale := int64(99)
	_, err = resourceStore.Put(ctx, user, "profile", "work", store.WriteInput{
		Data:             json.RawMessage(`{"name":"Changed"}`),
		ExpectedRevision: &stale,
	})
	if !errors.Is(err, store.ErrRevisionConflict) {
		t.Fatalf("Put(stale revision) error = %v, want ErrRevisionConflict", err)
	}
}

func TestResourceIdentityRequiresCanonicalLowercaseAcrossDialects(t *testing.T) {
	ctx := context.Background()
	db, resourceStore := testStore(t)
	user, _ := testUser(t, db, "canonical-identity", "canonical-encryption-key-material")
	for _, key := range []struct{ kind, id string }{
		{kind: "Profile", id: "work"},
		{kind: "profile", id: "Work"},
	} {
		_, err := resourceStore.Put(ctx, user, key.kind, key.id, store.WriteInput{
			Data: json.RawMessage(`{"name":"rejected"}`),
		})
		if !errors.Is(err, store.ErrInvalidResource) {
			t.Fatalf("Put(%q, %q) error = %v, want ErrInvalidResource", key.kind, key.id, err)
		}
	}
	if _, err := resourceStore.Put(ctx, user, "profile", "work", store.WriteInput{
		Data: json.RawMessage(`{"name":"accepted"}`),
	}); err != nil {
		t.Fatalf("Put(canonical key) error = %v", err)
	}
	_, err := resourceStore.Merge(ctx, user, store.MergeRequest{
		SchemaVersion: 1,
		SourceID:      "Foreign-Source",
		Resources:     []store.ResourceView{},
	})
	if !errors.Is(err, store.ErrInvalidResource) {
		t.Fatalf("Merge(uppercase source_id) error = %v, want ErrInvalidResource", err)
	}
}

func TestPutExpectedRevisionZeroCreatesOnlyWhenAbsent(t *testing.T) {
	ctx := context.Background()
	db, resourceStore := testStore(t)
	user, _ := testUser(t, db, "create-once", "create-once-encryption-key-material")
	createOnly := int64(0)

	created, err := resourceStore.Put(ctx, user, "profile", "default", store.WriteInput{
		Data:             json.RawMessage(`{"name":"First"}`),
		ExpectedRevision: &createOnly,
	})
	if err != nil {
		t.Fatalf("Put(create-if-absent) error = %v", err)
	}
	if created.Revision != 1 {
		t.Fatalf("Put(create-if-absent) revision = %d, want 1", created.Revision)
	}

	_, err = resourceStore.Put(ctx, user, "profile", "default", store.WriteInput{
		Data:             json.RawMessage(`{"name":"Lost update"}`),
		ExpectedRevision: &createOnly,
	})
	if !errors.Is(err, store.ErrRevisionConflict) {
		t.Fatalf("Put(create-if-present) error = %v, want ErrRevisionConflict", err)
	}
	preserved, err := resourceStore.Get(ctx, user, "profile", "default", false)
	if err != nil {
		t.Fatalf("Get(preserved) error = %v", err)
	}
	if string(preserved.Data) != `{"name":"First"}` || preserved.Revision != 1 {
		t.Fatalf("resource after rejected create = %#v", preserved)
	}
}

func TestPutExpectedRevisionZeroRecreatesDeletedResource(t *testing.T) {
	ctx := context.Background()
	db, resourceStore := testStore(t)
	user, _ := testUser(t, db, "recreate-deleted", "recreate-deleted-encryption-key")
	createOnly := int64(0)

	created, err := resourceStore.Put(ctx, user, "profile", "default", store.WriteInput{
		Data:             json.RawMessage(`{"name":"Original"}`),
		Sensitive:        json.RawMessage(`{"password":"deleted-secret"}`),
		SensitivePresent: true,
		ExpectedRevision: &createOnly,
	})
	if err != nil {
		t.Fatalf("Put(original) error = %v", err)
	}
	if err := resourceStore.Delete(ctx, user, "profile", "default", &created.Revision); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	if _, err := resourceStore.Get(ctx, user, "profile", "default", false); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("Get(deleted) error = %v, want ErrNotFound", err)
	}

	recreated, err := resourceStore.Put(ctx, user, "profile", "default", store.WriteInput{
		Data:             json.RawMessage(`{"name":"Recreated"}`),
		ClearSensitive:   true,
		ExpectedRevision: &createOnly,
	})
	if err != nil {
		t.Fatalf("Put(recreated) error = %v", err)
	}
	if recreated.Revision != created.Revision+2 || recreated.Deleted || recreated.HasSensitive {
		t.Fatalf("Put(recreated) = %#v", recreated)
	}
	if string(recreated.Data) != `{"name":"Recreated"}` {
		t.Fatalf("Put(recreated).Data = %s", recreated.Data)
	}

	_, err = resourceStore.Put(ctx, user, "profile", "default", store.WriteInput{
		Data:             json.RawMessage(`{"name":"Lost update"}`),
		ExpectedRevision: &createOnly,
	})
	if !errors.Is(err, store.ErrRevisionConflict) {
		t.Fatalf("Put(recreate-if-live) error = %v, want ErrRevisionConflict", err)
	}
}

func TestConcurrentCreateIfAbsentHasExactlyOneWinner(t *testing.T) {
	ctx := context.Background()
	db, resourceStore := testStore(t)
	user, _ := testUser(t, db, "concurrent-create", "concurrent-create-encryption-key")
	start := make(chan struct{})
	type result struct {
		name string
		err  error
	}
	results := make(chan result, 2)
	for _, name := range []string{"First", "Second"} {
		go func() {
			<-start
			createOnly := int64(0)
			_, err := resourceStore.Put(ctx, user, "profile", "default", store.WriteInput{
				Data:             json.RawMessage(`{"name":"` + name + `"}`),
				ExpectedRevision: &createOnly,
			})
			results <- result{name: name, err: err}
		}()
	}
	close(start)

	winners := make([]string, 0, 1)
	conflicts := 0
	for range 2 {
		outcome := <-results
		switch {
		case outcome.err == nil:
			winners = append(winners, outcome.name)
		case errors.Is(outcome.err, store.ErrRevisionConflict):
			conflicts++
		default:
			t.Fatalf("concurrent Put(%s) error = %v", outcome.name, outcome.err)
		}
	}
	if len(winners) != 1 || conflicts != 1 {
		t.Fatalf("concurrent create winners = %v, conflicts = %d", winners, conflicts)
	}

	persisted, err := resourceStore.Get(ctx, user, "profile", "default", false)
	if err != nil {
		t.Fatalf("Get(concurrent winner) error = %v", err)
	}
	if persisted.Revision != 1 || string(persisted.Data) != `{"name":"`+winners[0]+`"}` {
		t.Fatalf("concurrent create persisted = %#v, winner = %v", persisted, winners)
	}
}

func TestResourcePageSnapshotExcludesLaterInsertsAndRejectsCursorTampering(t *testing.T) {
	ctx := context.Background()
	writerDB, resourceStore, readerDB, pageStore := testStorePair(t)
	writerDB.Config.NowFunc = func() time.Time { return time.Now().UTC().Add(24 * time.Hour) }
	readerDB.Config.NowFunc = func() time.Time { return time.Now().UTC().Add(-24 * time.Hour) }
	user, _ := testUser(t, writerDB, "snapshot-page", "snapshot-page-encryption-key")
	for _, id := range []string{"first", "second", "third"} {
		if _, err := resourceStore.Put(ctx, user, "config", id, store.WriteInput{
			Data: json.RawMessage(`{"present_at_snapshot":true}`),
		}); err != nil {
			t.Fatalf("Put(%s) error = %v", id, err)
		}
	}

	insertAfterFirstPage := make(chan struct{})
	inserted := make(chan error, 1)
	go func() {
		<-insertAfterFirstPage
		// MySQL stores GORM timestamps at millisecond precision by default.
		// Move past that boundary so the shared contract exercises the cutoff
		// rather than depending on scheduler timing.
		time.Sleep(5 * time.Millisecond)
		_, err := resourceStore.Put(ctx, user, "config", "zz-after-snapshot", store.WriteInput{
			Data: json.RawMessage(`{"present_at_snapshot":false}`),
		})
		inserted <- err
	}()

	first, err := pageStore.List(ctx, user, "", false, false, 2, "")
	if err != nil {
		t.Fatalf("List(first snapshot page) error = %v", err)
	}
	if len(first.Resources) != 2 || first.NextCursor == "" {
		t.Fatalf("first snapshot page = %#v", first)
	}
	close(insertAfterFirstPage)
	if err := <-inserted; err != nil {
		t.Fatalf("Put(post-snapshot) error = %v", err)
	}

	tampered := "A" + first.NextCursor[1:]
	if _, err := pageStore.List(ctx, user, "", false, false, 2, tampered); !errors.Is(err, store.ErrInvalidPage) {
		t.Fatalf("List(tampered cursor) error = %v, want ErrInvalidPage", err)
	}
	if _, err := pageStore.List(ctx, user, "", true, false, 2, first.NextCursor); !errors.Is(err, store.ErrInvalidPage) {
		t.Fatalf("List(cursor with changed filters) error = %v, want ErrInvalidPage", err)
	}

	second, err := pageStore.List(ctx, user, "", false, false, 2, first.NextCursor)
	if err != nil {
		t.Fatalf("List(second snapshot page) error = %v", err)
	}
	if len(second.Resources) != 1 || second.Resources[0].ID != "third" || second.NextCursor != "" {
		t.Fatalf("second snapshot page = %#v", second)
	}
	fresh, err := pageStore.List(ctx, user, "", false, false, store.MaximumPageLimit, "")
	if err != nil {
		t.Fatalf("List(fresh snapshot) error = %v", err)
	}
	if len(fresh.Resources) != 4 {
		t.Fatalf("fresh snapshot resources = %d, want 4", len(fresh.Resources))
	}
}

func TestPaginatedExportCanBeMergedWithoutLossOrDuplication(t *testing.T) {
	ctx := context.Background()
	sourceDB, sourceStore := testStore(t)
	sourceUser, _ := testUser(t, sourceDB, "page-source", "page-source-encryption-key")
	destinationDB, destinationStore := testStore(t)
	destinationUser, _ := testUser(t, destinationDB, "page-destination", "page-destination-encryption-key")

	for index := range 5 {
		kind := "profile"
		if index < 2 {
			kind = "config"
		}
		id := fmt.Sprintf("item-%02d", index)
		if _, err := sourceStore.Put(ctx, sourceUser, kind, id, store.WriteInput{
			Data: json.RawMessage(fmt.Sprintf(`{"index":%d}`, index)),
		}); err != nil {
			t.Fatalf("Put(%s/%s) error = %v", kind, id, err)
		}
	}

	cursor := ""
	exported := make(map[string]struct{})
	var exportedAt time.Time
	for pageNumber := 1; ; pageNumber++ {
		bundle, err := sourceStore.Export(ctx, sourceUser, false, false, 2, cursor)
		if err != nil {
			t.Fatalf("Export(page %d) error = %v", pageNumber, err)
		}
		encoded, err := json.Marshal(bundle)
		if err != nil {
			t.Fatalf("marshal export page %d: %v", pageNumber, err)
		}
		if len(encoded) > store.MaximumJSONResponseBytes {
			t.Fatalf("export page %d bytes = %d, max = %d", pageNumber, len(encoded), store.MaximumJSONResponseBytes)
		}
		if pageNumber == 1 {
			exportedAt = bundle.ExportedAt
		} else if !bundle.ExportedAt.Equal(exportedAt) {
			t.Fatalf("Export(page %d).ExportedAt = %s, want snapshot %s", pageNumber, bundle.ExportedAt, exportedAt)
		}
		for _, resource := range bundle.Resources {
			key := resource.Kind + "/" + resource.ID
			if _, duplicate := exported[key]; duplicate {
				t.Fatalf("resource %s appeared in more than one export page", key)
			}
			exported[key] = struct{}{}
		}
		report, err := destinationStore.Merge(ctx, destinationUser, store.MergeRequest{
			SchemaVersion: bundle.SchemaVersion,
			SourceID:      bundle.SourceID,
			Resources:     bundle.Resources,
		})
		if err != nil {
			t.Fatalf("Merge(page %d) error = %v", pageNumber, err)
		}
		if report.Created != len(bundle.Resources) {
			t.Fatalf("Merge(page %d).Created = %d, want %d", pageNumber, report.Created, len(bundle.Resources))
		}
		if bundle.NextCursor == "" {
			break
		}
		cursor = bundle.NextCursor
	}
	if len(exported) != 5 {
		t.Fatalf("exported resources = %d, want 5", len(exported))
	}

	page, err := destinationStore.List(ctx, destinationUser, "", false, false, store.MaximumPageLimit, "")
	if err != nil {
		t.Fatalf("List(destination) error = %v", err)
	}
	if len(page.Resources) != 5 || page.NextCursor != "" {
		t.Fatalf("destination page = %#v", page)
	}
	_, err = destinationStore.Merge(ctx, destinationUser, store.MergeRequest{
		SchemaVersion: 1,
		SourceID:      sourceStore.ServerID(),
		Resources:     make([]store.ResourceView, store.MaximumPageLimit+1),
	})
	if !errors.Is(err, store.ErrInvalidResource) {
		t.Fatalf("Merge(oversized page) error = %v, want ErrInvalidResource", err)
	}
}

func TestListPageStopsBeforeDocumentedResponseByteLimit(t *testing.T) {
	ctx := context.Background()
	db, resourceStore := testStore(t)
	user, _ := testUser(t, db, "bounded-page", "bounded-page-encryption-key")
	payload, err := json.Marshal(map[string]string{
		"payload": strings.Repeat("x", 3<<20),
	})
	if err != nil {
		t.Fatalf("marshal bounded page fixture: %v", err)
	}
	for index := range 4 {
		id := fmt.Sprintf("large-%02d", index)
		if _, err := resourceStore.Put(ctx, user, "config", id, store.WriteInput{
			Data: payload,
		}); err != nil {
			t.Fatalf("Put(%s) error = %v", id, err)
		}
	}

	first, err := resourceStore.List(
		ctx,
		user,
		"",
		false,
		false,
		store.MaximumPageLimit,
		"",
	)
	if err != nil {
		t.Fatalf("List(first byte-bounded page) error = %v", err)
	}
	encoded, err := json.Marshal(first)
	if err != nil {
		t.Fatalf("marshal first byte-bounded page: %v", err)
	}
	if len(encoded) > store.MaximumJSONResponseBytes {
		t.Fatalf("first page bytes = %d, max = %d", len(encoded), store.MaximumJSONResponseBytes)
	}
	if len(first.Resources) >= 4 || first.NextCursor == "" {
		t.Fatalf("first byte-bounded page resources/cursor = %d/%q", len(first.Resources), first.NextCursor)
	}

	second, err := resourceStore.List(
		ctx,
		user,
		"",
		false,
		false,
		store.MaximumPageLimit,
		first.NextCursor,
	)
	if err != nil {
		t.Fatalf("List(second byte-bounded page) error = %v", err)
	}
	if len(first.Resources)+len(second.Resources) != 4 || second.NextCursor != "" {
		t.Fatalf(
			"byte-bounded pages resources/cursor = %d+%d/%q",
			len(first.Resources),
			len(second.Resources),
			second.NextCursor,
		)
	}
}

func TestPreserveDestinationAppliesOnlyMonotonicSameSourceUpdates(t *testing.T) {
	ctx := context.Background()
	// testStore defaults to SQLite and selects an isolated MySQL database when
	// IANVS_TEST_DATABASE_DRIVER=mysql, so this entire scenario is the shared
	// cross-dialect contract exercised by the MySQL workflow.
	sourceDB, sourceStore := testStore(t)
	sourceUser, _ := testUser(t, sourceDB, "monotonic-source", "monotonic-source-key-material")
	destinationDB, destinationStore := testStore(t)
	destinationUser, _ := testUser(t, destinationDB, "monotonic-destination", "monotonic-destination-key")

	if _, err := sourceStore.Put(ctx, sourceUser, "profile", "shared", store.WriteInput{
		Data:             json.RawMessage(`{"version":1}`),
		Sensitive:        json.RawMessage(`{"token":"first"}`),
		SensitivePresent: true,
	}); err != nil {
		t.Fatalf("source Put(initial) error = %v", err)
	}
	initial, err := sourceStore.Export(ctx, sourceUser, false, true, 1, "")
	if err != nil {
		t.Fatalf("Export(initial) error = %v", err)
	}
	initialRequest := store.MergeRequest{
		SchemaVersion: initial.SchemaVersion,
		SourceID:      initial.SourceID,
		Resources:     initial.Resources,
	}
	report, err := destinationStore.Merge(ctx, destinationUser, initialRequest)
	if err != nil {
		t.Fatalf("Merge(initial) error = %v", err)
	}
	if report.Created != 1 {
		t.Fatalf("Merge(initial) = %#v", report)
	}

	if _, err := sourceStore.Put(ctx, sourceUser, "profile", "shared", store.WriteInput{
		Data:             json.RawMessage(`{"version":2}`),
		Sensitive:        json.RawMessage(`{"token":"second"}`),
		SensitivePresent: true,
	}); err != nil {
		t.Fatalf("source Put(higher revision) error = %v", err)
	}
	higher, err := sourceStore.Export(ctx, sourceUser, false, true, 1, "")
	if err != nil {
		t.Fatalf("Export(higher revision) error = %v", err)
	}
	higherRequest := store.MergeRequest{
		SchemaVersion: higher.SchemaVersion,
		SourceID:      higher.SourceID,
		Resources:     higher.Resources,
	}
	report, err = destinationStore.Merge(ctx, destinationUser, higherRequest)
	if err != nil {
		t.Fatalf("Merge(higher same source) error = %v", err)
	}
	if report.Updated != 1 || report.Conflicts != 0 {
		t.Fatalf("Merge(higher same source) = %#v", report)
	}
	updated, err := destinationStore.Get(ctx, destinationUser, "profile", "shared", true)
	if err != nil {
		t.Fatalf("Get(higher same source) error = %v", err)
	}
	if string(updated.Data) != `{"version":2}` ||
		string(updated.Sensitive) != `{"token":"second"}` ||
		updated.Revision != 2 || updated.SourceRevision != 2 ||
		updated.SourceID != sourceStore.ServerID() {
		t.Fatalf("higher same-source resource = %#v", updated)
	}

	equalPlainMismatch := higher.Resources[0]
	equalPlainMismatch.Data = json.RawMessage(`{"version":"same-revision-different"}`)
	report, err = destinationStore.Merge(ctx, destinationUser, store.MergeRequest{
		SchemaVersion: higher.SchemaVersion,
		SourceID:      higher.SourceID,
		Resources:     []store.ResourceView{equalPlainMismatch},
	})
	if err != nil {
		t.Fatalf("Merge(equal revision, different plain data) error = %v", err)
	}
	if report.Conflicts != 1 || report.Updated != 0 || len(report.Results) != 1 ||
		!strings.Contains(report.Results[0].Reason, "same source revision") {
		t.Fatalf("Merge(equal revision, different plain data) = %#v", report)
	}

	equalSensitiveMismatch := higher.Resources[0]
	equalSensitiveMismatch.Sensitive = json.RawMessage(`{"token":"same-revision-different"}`)
	report, err = destinationStore.Merge(ctx, destinationUser, store.MergeRequest{
		SchemaVersion: higher.SchemaVersion,
		SourceID:      higher.SourceID,
		Resources:     []store.ResourceView{equalSensitiveMismatch},
	})
	if err != nil {
		t.Fatalf("Merge(equal revision, different sensitive data) error = %v", err)
	}
	if report.Conflicts != 1 || report.Updated != 0 || len(report.Results) != 1 ||
		!strings.Contains(report.Results[0].Reason, "same source revision") {
		t.Fatalf("Merge(equal revision, different sensitive data) = %#v", report)
	}
	unchangedAfterEqualConflict, err := destinationStore.Get(ctx, destinationUser, "profile", "shared", true)
	if err != nil {
		t.Fatalf("Get(after equal-revision conflicts) error = %v", err)
	}
	if string(unchangedAfterEqualConflict.Data) != `{"version":2}` ||
		string(unchangedAfterEqualConflict.Sensitive) != `{"token":"second"}` ||
		unchangedAfterEqualConflict.Revision != updated.Revision ||
		unchangedAfterEqualConflict.SourceRevision != updated.SourceRevision {
		t.Fatalf("equal-revision conflict changed destination = %#v", unchangedAfterEqualConflict)
	}

	report, err = destinationStore.Merge(ctx, destinationUser, higherRequest)
	if err != nil {
		t.Fatalf("Merge(replay) error = %v", err)
	}
	if report.Skipped != 1 || report.Updated != 0 {
		t.Fatalf("Merge(replay) = %#v", report)
	}
	replayed, err := destinationStore.Get(ctx, destinationUser, "profile", "shared", true)
	if err != nil {
		t.Fatalf("Get(replay) error = %v", err)
	}
	if replayed.Revision != updated.Revision || replayed.SourceRevision != updated.SourceRevision {
		t.Fatalf("replay advanced revisions: before=%#v after=%#v", updated, replayed)
	}

	report, err = destinationStore.Merge(ctx, destinationUser, initialRequest)
	if err != nil {
		t.Fatalf("Merge(lower source revision) error = %v", err)
	}
	if report.Skipped != 1 || report.Updated != 0 {
		t.Fatalf("Merge(lower source revision) = %#v", report)
	}

	foreign := higher.Resources[0]
	foreign.Data = json.RawMessage(`{"version":"foreign"}`)
	foreign.SourceRevision = higher.Resources[0].SourceRevision + 100
	report, err = destinationStore.Merge(ctx, destinationUser, store.MergeRequest{
		SchemaVersion: 1,
		SourceID:      "foreign-source",
		Resources:     []store.ResourceView{foreign},
	})
	if err != nil {
		t.Fatalf("Merge(foreign source) error = %v", err)
	}
	if report.Conflicts != 1 || report.Updated != 0 {
		t.Fatalf("Merge(foreign source) = %#v", report)
	}
	preserved, err := destinationStore.Get(ctx, destinationUser, "profile", "shared", true)
	if err != nil {
		t.Fatalf("Get(after foreign source) error = %v", err)
	}
	if string(preserved.Data) != `{"version":2}` || string(preserved.Sensitive) != `{"token":"second"}` {
		t.Fatalf("foreign source changed destination = %#v", preserved)
	}

	if _, err := sourceStore.Put(ctx, sourceUser, "profile", "shared", store.WriteInput{
		Data: json.RawMessage(`{"version":3}`),
	}); err != nil {
		t.Fatalf("source Put(higher revision without sensitive data) error = %v", err)
	}
	higherWithoutSensitive, err := sourceStore.Export(ctx, sourceUser, false, false, 1, "")
	if err != nil {
		t.Fatalf("Export(higher revision without sensitive data) error = %v", err)
	}
	report, err = destinationStore.Merge(ctx, destinationUser, store.MergeRequest{
		SchemaVersion: higherWithoutSensitive.SchemaVersion,
		SourceID:      higherWithoutSensitive.SourceID,
		Resources:     higherWithoutSensitive.Resources,
	})
	if err != nil {
		t.Fatalf("Merge(higher revision without sensitive data) error = %v", err)
	}
	if report.Updated != 1 || report.Conflicts != 0 {
		t.Fatalf("Merge(higher revision without sensitive data) = %#v", report)
	}
	preservedSensitive, err := destinationStore.Get(ctx, destinationUser, "profile", "shared", true)
	if err != nil {
		t.Fatalf("Get(after higher revision without sensitive data) error = %v", err)
	}
	if string(preservedSensitive.Data) != `{"version":3}` ||
		string(preservedSensitive.Sensitive) != `{"token":"second"}` ||
		preservedSensitive.Revision != 3 || preservedSensitive.SourceRevision != 3 {
		t.Fatalf("higher revision without sensitive data = %#v", preservedSensitive)
	}

	if err := sourceStore.Delete(ctx, sourceUser, "profile", "shared", nil); err != nil {
		t.Fatalf("source Delete() error = %v", err)
	}
	deleted, err := sourceStore.Export(ctx, sourceUser, true, false, 1, "")
	if err != nil {
		t.Fatalf("Export(deleted) error = %v", err)
	}
	deletedRequest := store.MergeRequest{
		SchemaVersion:    deleted.SchemaVersion,
		SourceID:         deleted.SourceID,
		PropagateDeletes: false,
		Resources:        deleted.Resources,
	}
	report, err = destinationStore.Merge(ctx, destinationUser, deletedRequest)
	if err != nil {
		t.Fatalf("Merge(deletion disabled) error = %v", err)
	}
	if report.Skipped != 1 || report.Deleted != 0 {
		t.Fatalf("Merge(deletion disabled) = %#v", report)
	}
	if _, err := destinationStore.Get(ctx, destinationUser, "profile", "shared", false); err != nil {
		t.Fatalf("Get(after disabled deletion) error = %v", err)
	}

	deletedRequest.PropagateDeletes = true
	report, err = destinationStore.Merge(ctx, destinationUser, deletedRequest)
	if err != nil {
		t.Fatalf("Merge(deletion enabled) error = %v", err)
	}
	if report.Deleted != 1 {
		t.Fatalf("Merge(deletion enabled) = %#v", report)
	}
	tombstones, err := destinationStore.List(ctx, destinationUser, "profile", true, false, 1, "")
	if err != nil {
		t.Fatalf("List(tombstone) error = %v", err)
	}
	if len(tombstones.Resources) != 1 || !tombstones.Resources[0].Deleted ||
		tombstones.Resources[0].HasSensitive || tombstones.Resources[0].Revision != 4 ||
		tombstones.Resources[0].SourceRevision != 4 {
		t.Fatalf("tombstone = %#v", tombstones)
	}

	report, err = destinationStore.Merge(ctx, destinationUser, deletedRequest)
	if err != nil {
		t.Fatalf("Merge(deletion replay) error = %v", err)
	}
	if report.Skipped != 1 || report.Deleted != 0 {
		t.Fatalf("Merge(deletion replay) = %#v", report)
	}
}

func TestOneWayMergeIsIdempotentAndPreservesDestinationConflicts(t *testing.T) {
	ctx := context.Background()
	sourceDB, sourceStore := testStore(t)
	sourceUser, _ := testUser(t, sourceDB, "source", "source-encryption-key-material")
	destinationDB, destinationStore := testStore(t)
	destinationUser, _ := testUser(t, destinationDB, "destination", "destination-encryption-key-material")

	_, err := sourceStore.Put(ctx, sourceUser, "profile", "work", store.WriteInput{
		Data:             json.RawMessage(`{"name":"Local work"}`),
		Sensitive:        json.RawMessage(`{"password":"local-secret"}`),
		SensitivePresent: true,
	})
	if err != nil {
		t.Fatalf("source Put() error = %v", err)
	}
	bundle, err := sourceStore.Export(ctx, sourceUser, false, true, store.DefaultPageLimit, "")
	if err != nil {
		t.Fatalf("Export() error = %v", err)
	}
	request := store.MergeRequest{
		SchemaVersion: bundle.SchemaVersion,
		SourceID:      bundle.SourceID,
		Resources:     bundle.Resources,
	}
	report, err := destinationStore.Merge(ctx, destinationUser, request)
	if err != nil {
		t.Fatalf("Merge() error = %v", err)
	}
	if report.Created != 1 || report.Conflicts != 0 {
		t.Fatalf("first Merge() = %#v", report)
	}
	migrated, err := destinationStore.Get(ctx, destinationUser, "profile", "work", true)
	if err != nil {
		t.Fatalf("Get(migrated) error = %v", err)
	}
	if string(migrated.Sensitive) != `{"password":"local-secret"}` {
		t.Fatalf("migrated sensitive data = %s", migrated.Sensitive)
	}

	report, err = destinationStore.Merge(ctx, destinationUser, request)
	if err != nil {
		t.Fatalf("second Merge() error = %v", err)
	}
	if report.Skipped != 1 || report.Created != 0 || report.Updated != 0 {
		t.Fatalf("idempotent Merge() = %#v", report)
	}

	_, err = destinationStore.Put(ctx, destinationUser, "profile", "work", store.WriteInput{
		Data: json.RawMessage(`{"name":"Remote edit"}`),
	})
	if err != nil {
		t.Fatalf("destination Put() error = %v", err)
	}
	_, err = sourceStore.Put(ctx, sourceUser, "profile", "work", store.WriteInput{
		Data: json.RawMessage(`{"name":"New local edit"}`),
	})
	if err != nil {
		t.Fatalf("source update error = %v", err)
	}
	newBundle, err := sourceStore.Export(ctx, sourceUser, false, true, store.DefaultPageLimit, "")
	if err != nil {
		t.Fatalf("second Export() error = %v", err)
	}
	report, err = destinationStore.Merge(ctx, destinationUser, store.MergeRequest{
		SchemaVersion: newBundle.SchemaVersion,
		SourceID:      newBundle.SourceID,
		Resources:     newBundle.Resources,
	})
	if err != nil {
		t.Fatalf("conflicting Merge() error = %v", err)
	}
	if report.Conflicts != 1 {
		t.Fatalf("conflicting Merge() = %#v", report)
	}
	preserved, err := destinationStore.Get(ctx, destinationUser, "profile", "work", false)
	if err != nil {
		t.Fatalf("Get(preserved) error = %v", err)
	}
	if string(preserved.Data) != `{"name":"Remote edit"}` {
		t.Fatalf("destination data was overwritten: %s", preserved.Data)
	}

	if err := sourceStore.Delete(ctx, sourceUser, "profile", "work", nil); err != nil {
		t.Fatalf("source Delete() error = %v", err)
	}
	deletedBundle, err := sourceStore.Export(ctx, sourceUser, true, false, store.DefaultPageLimit, "")
	if err != nil {
		t.Fatalf("deleted Export() error = %v", err)
	}
	report, err = destinationStore.Merge(ctx, destinationUser, store.MergeRequest{
		SchemaVersion:    deletedBundle.SchemaVersion,
		SourceID:         deletedBundle.SourceID,
		PropagateDeletes: true,
		Resources:        deletedBundle.Resources,
	})
	if err != nil {
		t.Fatalf("deletion Merge() error = %v", err)
	}
	if report.Deleted != 1 {
		t.Fatalf("deletion Merge() = %#v", report)
	}
	if _, err := destinationStore.Get(ctx, destinationUser, "profile", "work", false); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("Get(deleted) error = %v, want ErrNotFound", err)
	}
}

func testStore(t *testing.T) (*gorm.DB, *store.Store) {
	t.Helper()
	cfg, cleanup, err := contracttest.NewDatabaseConfiguration(
		context.Background(),
		config.ModeLocal,
		filepath.Join(t.TempDir(), "test.db"),
	)
	if err != nil {
		t.Fatalf("create contract database configuration: %v", err)
	}
	t.Cleanup(func() {
		if err := cleanup(); err != nil {
			t.Errorf("clean up contract database: %v", err)
		}
	})
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
			t.Errorf("close contract database: %v", err)
		}
	})
	resourceStore, err := store.New(context.Background(), db)
	if err != nil {
		t.Fatalf("store.New() error = %v", err)
	}
	return db, resourceStore
}

func testStorePair(t *testing.T) (*gorm.DB, *store.Store, *gorm.DB, *store.Store) {
	t.Helper()
	cfg, cleanup, err := contracttest.NewDatabaseConfiguration(
		context.Background(),
		config.ModeLocal,
		filepath.Join(t.TempDir(), "pair.db"),
	)
	if err != nil {
		t.Fatalf("create paired contract database configuration: %v", err)
	}
	t.Cleanup(func() {
		if err := cleanup(); err != nil {
			t.Errorf("clean up paired contract database: %v", err)
		}
	})
	openStore := func(name string) (*gorm.DB, *store.Store) {
		db, err := database.Open(cfg)
		if err != nil {
			t.Fatalf("database.Open(%s) error = %v", name, err)
		}
		sqlDB, err := db.DB()
		if err != nil {
			t.Fatalf("database pool(%s) error = %v", name, err)
		}
		t.Cleanup(func() {
			if err := sqlDB.Close(); err != nil {
				t.Errorf("close paired contract database %s: %v", name, err)
			}
		})
		resourceStore, err := store.New(context.Background(), db)
		if err != nil {
			t.Fatalf("store.New(%s) error = %v", name, err)
		}
		return db, resourceStore
	}
	writerDB, writerStore := openStore("writer")
	readerDB, readerStore := openStore("reader")
	return writerDB, writerStore, readerDB, readerStore
}

func testUser(t *testing.T, db *gorm.DB, username, encryptionKey string) (model.User, []byte) {
	t.Helper()
	id, err := identity.UUID()
	if err != nil {
		t.Fatalf("identity.UUID() error = %v", err)
	}
	user := model.User{ID: id, Username: username}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	return user, []byte(encryptionKey)
}
