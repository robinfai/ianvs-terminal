#ifndef IANVS_CORE_H
#define IANVS_CORE_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define HOST_REQUEST_SCHEMA_VERSION 1

#define MAX_HOST_REQUEST_BYTES (64 * 1024)

#define MAX_HOST_RESPONSE_BYTES ((6 * 1024) * 1024)

#define DEFAULT_SCROLLBACK_LINES 8000

#define MAX_SCROLLBACK_LINES 100000

#define RUNTIME_CAPABILITIES_SCHEMA_VERSION 1

#define RUNTIME_ENVELOPE_SCHEMA_VERSION 1

#define FRAME_PACKET_SCHEMA_VERSION 1

#define GRAPHIC_ASSET_PACKET_SCHEMA_VERSION 1

#define GRAPHIC_ASSET_PACKET_MAX_RGBA_BYTES ((100 * 1024) * 1024)

#define REFRESH_HINT_FRAME_DIRTY (1 << 0)

#define REFRESH_HINT_EVENT_PENDING (1 << 1)

#define REFRESH_HINT_EXIT_PENDING (1 << 2)

#define SESSION_CONFIG_SCHEMA_VERSION 1

#define MAX_SESSION_CONFIG_BYTES (1024 * 1024)

#define SESSION_REQUEST_SCHEMA_VERSION 1

#define MAX_SESSION_REQUEST_BYTES (1024 * 1024)

#define MAX_SESSION_RESPONSE_BYTES ((16 * 1024) * 1024)

typedef struct IanvsGraphicAssetMeta {
  uint32_t width;
  uint32_t height;
  uintptr_t rgba_len;
  uint64_t version;
} IanvsGraphicAssetMeta;

int ianvs_ping(void);

char *ianvs_runtime_capabilities_json(void);

/**
 * Imports concrete OpenSSH Host entries using Tabby-compatible Include and
 * wildcard resolution. A null or empty path selects `~/.ssh/config`.
 *
 * # Safety
 *
 * When non-null, `config_path` must be a valid, NUL-terminated UTF-8 string
 * pointer that remains alive for the duration of this call.
 */
char *ianvs_ssh_import_profiles_json(const char *config_path);

/**
 * # Safety
 *
 * `profile_json` must be a valid, NUL-terminated UTF-8 string pointer that
 * remains alive for the duration of this call.
 */
uint64_t ianvs_session_create(const char *profile_json);

/**
 * Creates a live session from the product-neutral SessionConfig v1 contract.
 *
 * # Safety
 *
 * `session_config_json` must be a valid, NUL-terminated UTF-8 string pointer
 * that remains alive for the duration of this call.
 */
uint64_t ianvs_session_create_v1(const char *session_config_json);

/**
 * # Safety
 *
 * `profile_json` must be a valid, NUL-terminated UTF-8 string pointer that
 * remains alive for the duration of this call.
 */
uint64_t ianvs_replay_session_create(const char *profile_json);

/**
 * Creates a deterministic replay session from SessionConfig v1.
 *
 * # Safety
 *
 * `session_config_json` must be a valid, NUL-terminated UTF-8 string pointer
 * that remains alive for the duration of this call.
 */
uint64_t ianvs_replay_session_create_v1(const char *session_config_json);

/**
 * # Safety
 *
 * When `len` is non-zero, `bytes` must point to `len` readable bytes for the
 * duration of this call. When `len` is zero, `bytes` may be null.
 */
int ianvs_replay_session_output(uint64_t session_id, const uint8_t *bytes, uintptr_t len);

int ianvs_replay_session_exit(uint64_t session_id, int exit_code, int has_exit_code);

uint64_t ianvs_replay_session_checkpoint_capture(uint64_t session_id);

int ianvs_replay_session_checkpoint_restore(uint64_t session_id, uint64_t checkpoint_id);

int ianvs_session_close(uint64_t session_id);

uint32_t ianvs_session_refresh_hint(uint64_t session_id);

int ianvs_session_resize(uint64_t session_id,
                         uint16_t cols,
                         uint16_t rows,
                         uint16_t pixel_width,
                         uint16_t pixel_height);

int ianvs_session_resize_with_cell_size(uint64_t session_id,
                                        uint16_t cols,
                                        uint16_t rows,
                                        uint16_t pixel_width,
                                        uint16_t pixel_height,
                                        uint16_t cell_width,
                                        uint16_t cell_height);

/**
 * # Safety
 *
 * When `len` is non-zero, `bytes` must point to `len` readable bytes for the
 * duration of this call. When `len` is zero, `bytes` may be null.
 */
int ianvs_session_write(uint64_t session_id, const uint8_t *bytes, uintptr_t len);

/**
 * Writes a terminal/host protocol reply at the native ZMODEM ordering
 * boundary. If a transfer is active, the bytes are queued until its terminal
 * drain completes; user input must continue to use `ianvs_session_write`.
 *
 * # Safety
 *
 * When `len` is non-zero, `bytes` must point to `len` readable bytes for the
 * duration of this call. When `len` is zero, `bytes` may be null.
 */
int ianvs_session_write_protocol_reply(uint64_t session_id, const uint8_t *bytes, uintptr_t len);

/**
 * Consumes one correlated Host Response v1.
 *
 * # Safety
 *
 * `response_json` must be a valid, NUL-terminated UTF-8 string pointer that
 * remains alive for the duration of this call.
 */
int ianvs_session_host_response_v1_json(uint64_t session_id, const char *response_json);

int ianvs_session_scroll(uint64_t session_id, int32_t delta_lines);

int ianvs_session_scroll_to(uint64_t session_id, uintptr_t offset);

/**
 * # Safety
 *
 * `query` must be a valid, NUL-terminated UTF-8 string pointer that remains
 * alive for the duration of this call.
 */
char *ianvs_session_search_json(uint64_t session_id, const char *query);

/**
 * # Safety
 *
 * `request_json` must be a valid, NUL-terminated UTF-8 string pointer that
 * remains alive for the duration of this call.
 */
char *ianvs_session_selection_text(uint64_t session_id, const char *request_json);

/**
 * # Safety
 *
 * `request_json` must be a valid, NUL-terminated UTF-8 string pointer that
 * remains alive for the duration of this call.
 */
char *ianvs_session_request_json(uint64_t session_id, const char *request_json);

/**
 * Executes a correlated Session Request v1 and returns Session Response v1.
 *
 * # Safety
 *
 * `request_json` must be a valid, NUL-terminated UTF-8 string pointer that
 * remains alive for the duration of this call.
 */
char *ianvs_session_request_v1_json(uint64_t session_id, const char *request_json);

char *ianvs_session_take_frame_diff_json(uint64_t session_id);

/**
 * # Safety
 *
 * `out_len` must point to writable memory for one `usize`.
 */
uint8_t *ianvs_session_take_frame_diff_protobuf(uint64_t session_id, uintptr_t *out_len);

/**
 * Returns one correlated Terminal Frame Packet v1 as owned Protobuf bytes.
 *
 * `has_after_sequence` is zero before the first accepted packet and non-zero
 * when `after_sequence` contains the last packet sequence applied by Dart.
 * A stale acknowledgement forces the returned Frame payload to be a Snapshot.
 *
 * # Safety
 *
 * `out_len` must point to writable memory for one `usize`.
 */
uint8_t *ianvs_session_take_frame_packet_v1_protobuf(uint64_t session_id,
                                                     uint64_t after_sequence,
                                                     uint8_t has_after_sequence,
                                                     uintptr_t *out_len);

char *ianvs_session_take_frame_debug_stats_json(uint64_t session_id);

char *ianvs_session_take_session_debug_stats_json(uint64_t session_id);

/**
 * Returns a Diagnostic Event v1 Runtime Envelope for a supported diagnostic.
 *
 * # Safety
 *
 * `diagnostic_name` must be a valid, NUL-terminated UTF-8 string pointer that
 * remains alive for the duration of this call.
 */
char *ianvs_session_take_diagnostic_event_v1_json(uint64_t session_id, const char *diagnostic_name);

char *ianvs_session_poll_events_json(uint64_t session_id);

char *ianvs_session_poll_event_envelopes_json(uint64_t session_id);

/**
 * # Safety
 *
 * `out_meta` must point to writable memory for an `IanvsGraphicAssetMeta`.
 */
int ianvs_session_graphic_asset_meta(uint64_t session_id,
                                     uint64_t asset_id,
                                     uint64_t asset_version,
                                     struct IanvsGraphicAssetMeta *out_meta);

/**
 * Returns one Graphic Asset Packet v1 as owned Protobuf bytes.
 *
 * # Safety
 *
 * `out_len` must point to writable memory for one `usize`.
 */
uint8_t *ianvs_session_graphic_asset_packet_v1_protobuf(uint64_t session_id,
                                                        uint64_t asset_id,
                                                        uint64_t asset_version,
                                                        uintptr_t *out_len);

/**
 * # Safety
 *
 * `dst` must point to `len` writable bytes for the duration of this call.
 */
intptr_t ianvs_session_graphic_asset_rgba_copy(uint64_t session_id,
                                               uint64_t asset_id,
                                               uint64_t asset_version,
                                               uint8_t *dst,
                                               uintptr_t len);

/**
 * Atomically copies and consumes one completed OSC 1337 download.
 *
 * # Safety
 *
 * When `len` is non-zero, `dst` must point to `len` writable bytes for the
 * duration of this call. When `len` is zero, `dst` may be null.
 */
intptr_t ianvs_session_file_download_take(uint64_t session_id,
                                          uint64_t download_id,
                                          uint8_t *dst,
                                          uintptr_t len);

int ianvs_session_file_download_discard(uint64_t session_id, uint64_t download_id);

/**
 * # Safety
 *
 * `value` must be a pointer previously returned by this library via
 * `CString::into_raw`, and it must not be freed more than once.
 */
void ianvs_string_free(char *value);

/**
 * # Safety
 *
 * `ptr` must be a pointer returned by one of this library's owned Protobuf
 * Frame byte entrypoints with the same `len`.
 */
void ianvs_bytes_free(uint8_t *ptr, uintptr_t len);

#endif  /* IANVS_CORE_H */
