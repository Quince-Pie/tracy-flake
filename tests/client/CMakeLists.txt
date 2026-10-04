cmake_minimum_required(VERSION 3.16)
project(tracy-consumer LANGUAGES CXX)

find_package(Tracy ${EXPECTED_TRACY_VERSION} EXACT REQUIRED CONFIG)
add_executable(tracy-consumer main.cpp)
set_target_properties(tracy-consumer PROPERTIES CXX_STANDARD 11 CXX_STANDARD_REQUIRED YES)
target_link_libraries(tracy-consumer PRIVATE Tracy::TracyClient)
install(TARGETS tracy-consumer DESTINATION bin)
