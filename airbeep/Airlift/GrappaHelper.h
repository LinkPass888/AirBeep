#ifndef GrappaHelper_h
#define GrappaHelper_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Generates an authentic Grappa client token for AirTraffic sync.
/// Returns 0 on success, or a negative error code on failure.
__attribute__((visibility("default"), used))
int ALGetGrappaToken(
    uint32_t in_version,
    uint32_t in_device_type,
    uint32_t in_protocol_version,
    uint8_t *out_buf,
    size_t max_len,
    size_t *out_len,
    char *err_buf,
    size_t err_len
);

#ifdef __cplusplus
}
#endif

#endif /* GrappaHelper_h */
