//
//  CHelpers.c
//  VoiceChanger
//
//  C helpers for Swift interop
//

#include "include/CHelpers.h"
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>

int vc_shm_open(const char *name, int oflag, mode_t mode) {
    return shm_open(name, oflag, mode);
}

int vc_shm_unlink(const char *name) {
    return shm_unlink(name);
}

int vc_get_errno(void) {
    return errno;
}
