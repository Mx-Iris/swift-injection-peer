//
//  PeerProcessProbe.c
//  swift-injection-peer
//

#include "PeerProcessProbe.h"

// `sandbox_check` is SPI (declared in the private <sandbox.h>). Declare the
// prototype locally rather than importing the private header.
extern int sandbox_check(pid_t pid, const char *operation, uint32_t type, ...);

// Values from the private sandbox headers.
#define PeerProcessProbeSandboxFilterGlobalName 2u
#define PeerProcessProbeSandboxCheckNoReport 0x40000000u

int PeerProcessProbeSandboxCheckMachLookup(pid_t pid, const char *globalName) {
    // NO_REPORT suppresses the sandbox-violation log a plain probe would emit.
    return sandbox_check(pid,
                         "mach-lookup",
                         PeerProcessProbeSandboxFilterGlobalName | PeerProcessProbeSandboxCheckNoReport,
                         globalName);
}
