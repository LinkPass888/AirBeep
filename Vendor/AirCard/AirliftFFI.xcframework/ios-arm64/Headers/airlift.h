// Airlift Rust core — C FFI surface.
//
// All fallible calls return an int32 code (0 == OK). Heap strings must be
// released with al_string_free().
#ifndef AIRLIFT_H
#define AIRLIFT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

// Receives every formatted log line. `msg` is only valid for the duration of
// the call — copy it. May be called from arbitrary Rust threads.
typedef void (*ALLogCallback)(void *ctx, const char *msg);

// Install the global tracing subscriber. Returns 0 on success, 1 if already
// initialised. Call once at launch.
int32_t al_log_init(ALLogCallback cb, void *ctx);

// Free any char* returned by this library.
void al_string_free(char *p);

// ---------------------------------------------------------------------------
// Pairing — RPPairing host
// ---------------------------------------------------------------------------

// Fires once the host is bound. The Swift side publishes `service_id` over
// Bonjour (NetService). All pointers are only valid during the call.
typedef void (*ALPairReadyCb)(void *ctx,
                               const char *service_id,
                               uint16_t port,
                               const char *const *txt_keys,
                               const char *const *txt_vals,
                               size_t txt_count);

// Fires with the PIN the user must confirm in Settings → Developer Mode.
typedef void (*ALPairPinCb)(const char *pin, void *ctx);

// Heap-allocated result of one pairing run. Free with al_pairing_result_free().
typedef struct {
    char *error;
    char *device_name;
    char *device_model;
    char *device_udid;
    char *pairing_file_path;
    char *host_alt_irk_hex;
} ALPairResult;

// Run the RPPairing host. BLOCKS until paired or errored — run off main thread.
// `port` 0 lets the OS pick a free port.
// `host_alt_irk_hex` is the value a previous run returned, or NULL/"" first time.
// Returns 0 on success, non-zero on error (with out->error set).
int32_t al_pairing_run_host(const char *bind_addr,
                             uint16_t port,
                             const char *name,
                             const char *model,
                             const char *out_path,
                             const char *host_alt_irk_hex,
                             ALPairReadyCb ready_cb,
                             ALPairPinCb pin_cb,
                             void *ctx,
                             ALPairResult *out);

// Free the heap strings inside an ALPairResult.
void al_pairing_result_free(ALPairResult *r);

// ---------------------------------------------------------------------------
// Exploit
// ---------------------------------------------------------------------------

// Run the AirTraffic sandbox escape. BLOCKS — run off the main thread.
// `pairing_path` — path produced by al_pairing_run_host.
// `target`       — absolute iOS directory (e.g. "/var/mobile/Library/SpringBoard").
// `log_cb`       — receives log lines (called from arbitrary threads; may be NULL).
// `out_json`     — set to a JSON result string; free with al_string_free().
// `out_error`    — set on failure; free with al_string_free().
// Returns 0 if the canary write was confirmed, 1 otherwise.
int32_t al_exploit_run(const char *pairing_path,
                        const char *target,
                        ALLogCallback log_cb,
                        void *ctx,
                        char **out_json,
                        char **out_error);

// Read one absolute iOS file through the AirTraffic exploit.
// `out_data` is heap-allocated and must be released with al_bytes_free(out_data, out_len).
int32_t al_exploit_read_file(const char *pairing_path,
                              const char *ios_path,
                              ALLogCallback log_cb,
                              void *ctx,
                              uint8_t **out_data,
                              size_t *out_len,
                              char **out_error);

// Free bytes returned by al_exploit_read_file().
void al_bytes_free(uint8_t *ptr, size_t len);

// Write all files from `source_dir` into `target_dir` on the device.
// Returns 0 on success, 1 on error (with out_error set).
int32_t al_exploit_write_dir(const char *pairing_path,
                             const char *source_dir,
                             const char *target_dir,
                             ALLogCallback log_cb,
                             void *ctx,
                             char **out_error);

// Inject an entire directory `folder_path` into `target_parent_dir/dest_name` on the device.
// Preserves complete folder hierarchy and all internal assets in one AirTraffic operation.
// Returns 0 on success, 1 on error (with out_error set).
int32_t al_exploit_inject_folder(const char *pairing_path,
                                 const char *folder_path,
                                 const char *target_parent_dir,
                                 const char *dest_name,
                                 ALLogCallback log_cb,
                                 void *ctx,
                                 char **out_error);

// ---------------------------------------------------------------------------
// Syslog Stream / Live Card Detection
// ---------------------------------------------------------------------------

typedef void (*ALSyslogLineCallback)(void *ctx, const char *line);

// Stream device syslog messages over RSD.
// Blocks until al_syslog_stream_stop() is called.
int32_t al_syslog_stream_start(const char *pairing_path,
                               ALSyslogLineCallback line_cb,
                               void *ctx,
                               char **out_error);

// Stop any running syslog stream.
void al_syslog_stream_stop(void);

// Extract all files from a .passthm archive into dest_dir. Returns 0 on success.
int32_t al_passthm_extract(const char *archive_path, const char *dest_dir);

// Extract all files and directories from a zip archive into dest_dir. Returns 0 on success.
int32_t al_zip_extract_all(const char *archive_path, const char *dest_dir);

// Look up the Data Application Container directory for a bundle ID (e.g. "com.apple.PosterBoard").
// Blocks until resolved or errored. Returns 0 on success, with out_container set.
int32_t al_find_app_container(const char *pairing_path,
                             const char *bundle_id,
                             ALLogCallback log_cb,
                             void *ctx,
                             char **out_container,
                             char **out_error);

// Restart device / respring via Diagnostics Relay over the pairing tunnel.
// Blocks until sent. Returns 0 on success.
int32_t al_device_respring(const char *pairing_path,
                          ALLogCallback log_cb,
                          void *ctx,
                          char **out_error);

// ---------------------------------------------------------------------------
// Target Host Configuration
// ---------------------------------------------------------------------------

// Set the primary target host/IP (e.g. "10.7.0.1") to dial first for RSD and tunnel operations.
// Passing NULL or "" resets to None.
// Returns 0 on success.
int32_t al_set_target_host(const char *host);

// Set additional candidate target hosts (e.g. from local interface discovery).
// `hosts` is an array of C-strings of length `count`.
// Returns 0 on success.
int32_t al_set_target_hosts(const char *const *hosts, size_t count);

// Clear custom target host settings, reverting to default tunnel IP fallbacks.
void al_clear_target_hosts(void);


#ifdef __cplusplus
}
#endif

#endif /* AIRLIFT_H */

