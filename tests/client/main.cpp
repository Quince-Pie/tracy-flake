#include <tracy/Tracy.hpp>
#include <tracy/TracyC.h>

#include <chrono>
#include <cstdio>
#include <thread>

#ifndef TRACY_ENABLE
#error The installed CMake target must propagate TRACY_ENABLE to consumers
#endif

int main(int argc, char**)
{
    if (argc == 1)
    {
        ZoneScopedN("nix-smoke");
        FrameMark;
        return 0;
    }

    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(15);
    while (!TracyIsConnected)
    {
        if (std::chrono::steady_clock::now() > deadline)
        {
            std::fputs("Capture did not connect\n", stderr);
            return 1;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    for (int i = 0; i < 8; ++i)
    {
        {
            ZoneScopedN("nix-cpp-zone");
            {
                ZoneScopedNS("nix-callstack-zone", 4);
                TracyCZoneN(c_zone, "nix-c-zone", 1);
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
                TracyCZoneEnd(c_zone);
            }
        }
        FrameMark;
    }
    TracyMessageL("nix-capture-complete");
    return 0;
}
