#include <stdbool.h>
#include <tracy/TracyC.h>

#if EXPECTED_TRACY_ENABLE && !defined(TRACY_ENABLE)
#error The installed pkg-config file must enable the C API
#elif !EXPECTED_TRACY_ENABLE && defined(TRACY_ENABLE)
#error The installed pkg-config file must not define TRACY_ENABLE when disabled
#endif

int main(void)
{
#if defined(TRACY_ENABLE) && defined(TRACY_FIBERS)
    TracyCFiberEnter("nix-c-fiber");
#endif
    TracyCZoneN(zone, "nix-c-consumer", true);
    TracyCZoneEnd(zone);
#if defined(TRACY_ENABLE) && defined(TRACY_FIBERS)
    TracyCFiberLeave;
#endif
    TracyCFrameMark;
    return 0;
}
