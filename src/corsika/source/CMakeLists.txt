cmake_minimum_required (VERSION 3.9)

project (CORSIKA8_examples)
set (CMAKE_VERBOSE_MAKEFILE OFF) # this can be changed with `make VERBOSE=1`

# this is enough to use CORSIKA8
find_package (corsika CONFIG REQUIRED)

# this is only for CORSIKA_REGISTER_EXAMPLE
include ("${CMAKE_CURRENT_SOURCE_DIR}/corsikaExamples.cmake")

# Put binaries in bin directory
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

add_executable (c8_air_shower c8_air_shower.cpp)
target_link_libraries (c8_air_shower PRIVATE CORSIKA8::CORSIKA8)
CORSIKA_REGISTER_EXAMPLE (c8_air_shower)

if(WITH_FLUKA)
  message("compiling c8_air_shower.cpp with FLUKA")
  target_compile_definitions(c8_air_shower PRIVATE WITH_FLUKA)
else()
  message("compiling c8_air_shower.cpp with UrQMD")
endif()

# Embed absolute paths to all linked shared libraries in the RPATH at configure time
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
