#include <stdbool.h>
#include <tracy/TracyC.h>

#ifndef TRACY_ENABLE
#error The installed pkg-config file must enable the C API
#endif

int main(void)
{
#ifdef TRACY_FIBERS
    TracyCFiberEnter("nix-c-fiber");
#endif
    TracyCZoneN(zone, "nix-c-consumer", true);
    TracyCZoneEnd(zone);
#ifdef TRACY_FIBERS
    TracyCFiberLeave;
#endif
    TracyCFrameMark;
    return 0;
}
