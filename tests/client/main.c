#include <stdbool.h>
#include <tracy/TracyC.h>

#ifndef TRACY_ENABLE
#error The installed pkg-config file must enable the C API
#endif

int main(void)
{
    TracyCZoneN(zone, "nix-c-consumer", true);
    TracyCZoneEnd(zone);
    TracyCFrameMark;
    return 0;
}
