//
//  CHelpers.h
//  VoiceChanger
//
//  C helpers for Swift interop
//

#ifndef CHelpers_h
#define CHelpers_h

#include <sys/types.h>

/// shm_open wrapper (variadic functions not callable from Swift)
int vc_shm_open(const char *name, int oflag, mode_t mode);

/// shm_unlink wrapper
int vc_shm_unlink(const char *name);

/// Get errno value
int vc_get_errno(void);

#endif /* CHelpers_h */
