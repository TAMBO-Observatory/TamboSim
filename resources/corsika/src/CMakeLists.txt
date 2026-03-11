cmake_minimum_required(VERSION 3.14)
project(tambo_shower CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Default to the local corsika_upstream build tree.
# Override with -Dcorsika_DIR=/path/to/corsikaConfig.cmake dir.
# Dependencies (CLI11, Boost, etc.) are managed by Conan; pass the toolchain:
#   cmake -S . -B build \
#     -DCMAKE_TOOLCHAIN_FILE=$HOME/research/corsika/build/conan_toolchain.cmake
if(NOT DEFINED corsika_DIR)
  set(corsika_DIR "$ENV{HOME}/research/corsika_upstream/build"
      CACHE PATH "Directory containing corsikaConfig.cmake")
endif()

find_package(corsika REQUIRED)

add_executable(tambo_shower tambo_shower.cpp)
target_link_libraries(tambo_shower PRIVATE CORSIKA8::CORSIKA8)

set_target_properties(tambo_shower PROPERTIES
  BUILD_RPATH   "${corsika_DIR}"
  INSTALL_RPATH "$ORIGIN/../lib/corsika"
)

install(TARGETS tambo_shower DESTINATION bin)
