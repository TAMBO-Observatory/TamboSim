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

option(WITH_FLUKA "Use FLUKA as the low-energy hadronic model instead of UrQMD" OFF)

add_executable(tambo_shower tambo_shower.cpp)
target_link_libraries(tambo_shower PRIVATE CORSIKA8::CORSIKA8)

if(WITH_FLUKA)
  target_compile_definitions(tambo_shower PRIVATE WITH_FLUKA)
endif()

# Embed the GCC runtime lib directory so the binary runs without loading any
# compiler module.  The path is derived from the compiler itself so it works
# across different GCC module versions and installation prefixes.
execute_process(
  COMMAND ${CMAKE_CXX_COMPILER} -print-file-name=libstdc++.so
  OUTPUT_VARIABLE _GCC_STDCXX_LIB
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
# Resolve symlinks / ".." components using CMake's native REALPATH mode
get_filename_component(_GCC_STDCXX_REAL "${_GCC_STDCXX_LIB}" REALPATH)
get_filename_component(_GCC_LIB_DIR "${_GCC_STDCXX_REAL}" DIRECTORY)
message(STATUS "Embedding GCC runtime rpath: ${_GCC_LIB_DIR}")

set_target_properties(tambo_shower PROPERTIES
  BUILD_RPATH   "${corsika_DIR};${_GCC_LIB_DIR}"
  INSTALL_RPATH "$ORIGIN/../lib/corsika;${_GCC_LIB_DIR}"
)

install(TARGETS tambo_shower DESTINATION bin)
