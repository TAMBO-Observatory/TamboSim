

# Conan automatically generated toolchain file
# DO NOT EDIT MANUALLY, it will be overwritten

# Avoid including toolchain file several times (bad if appending to variables like
#   CMAKE_CXX_FLAGS. See https://github.com/android/ndk/issues/323
include_guard()

message(STATUS "Using Conan toolchain: ${CMAKE_CURRENT_LIST_FILE}")

if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeToolchain' generator only works with CMake >= 3.15")
endif()




########## generic_system block #############
# Definition of system, platform and toolset
#############################################







string(APPEND CONAN_CXX_FLAGS " -m64")
string(APPEND CONAN_C_FLAGS " -m64")
string(APPEND CONAN_SHARED_LINKER_FLAGS " -m64")
string(APPEND CONAN_EXE_LINKER_FLAGS " -m64")



message(STATUS "Conan toolchain: C++ Standard 17 with extensions ON")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)


# Conan conf flags start: 
# Conan conf flags end

foreach(config IN LISTS CMAKE_CONFIGURATION_TYPES)
    string(TOUPPER ${config} config)
    if(DEFINED CONAN_CXX_FLAGS_${config})
      string(APPEND CMAKE_CXX_FLAGS_${config}_INIT " ${CONAN_CXX_FLAGS_${config}}")
    endif()
    if(DEFINED CONAN_C_FLAGS_${config})
      string(APPEND CMAKE_C_FLAGS_${config}_INIT " ${CONAN_C_FLAGS_${config}}")
    endif()
    if(DEFINED CONAN_SHARED_LINKER_FLAGS_${config})
      string(APPEND CMAKE_SHARED_LINKER_FLAGS_${config}_INIT " ${CONAN_SHARED_LINKER_FLAGS_${config}}")
    endif()
    if(DEFINED CONAN_EXE_LINKER_FLAGS_${config})
      string(APPEND CMAKE_EXE_LINKER_FLAGS_${config}_INIT " ${CONAN_EXE_LINKER_FLAGS_${config}}")
    endif()
endforeach()

if(DEFINED CONAN_CXX_FLAGS)
  string(APPEND CMAKE_CXX_FLAGS_INIT " ${CONAN_CXX_FLAGS}")
endif()
if(DEFINED CONAN_C_FLAGS)
  string(APPEND CMAKE_C_FLAGS_INIT " ${CONAN_C_FLAGS}")
endif()
if(DEFINED CONAN_SHARED_LINKER_FLAGS)
  string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " ${CONAN_SHARED_LINKER_FLAGS}")
endif()
if(DEFINED CONAN_EXE_LINKER_FLAGS)
  string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " ${CONAN_EXE_LINKER_FLAGS}")
endif()




get_property( _CMAKE_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
if(_CMAKE_IN_TRY_COMPILE)
    message(STATUS "Running toolchain IN_TRY_COMPILE")
    return()
endif()

set(CMAKE_FIND_PACKAGE_PREFER_CONFIG ON)

# Definition of CMAKE_MODULE_PATH
list(PREPEND CMAKE_MODULE_PATH "/n/home09/tkrishnan/.conan2/p/b/catch75024f1338965/p/lib/cmake/Catch2" "/n/home09/tkrishnan/.conan2/p/b/opensc20ff3cad4ee2/p/lib/cmake")
# the generators folder (where conan generates files, like this toolchain)
list(PREPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR})

# Definition of CMAKE_PREFIX_PATH, CMAKE_XXXXX_PATH
# The explicitly defined "builddirs" of "host" context dependencies must be in PREFIX_PATH
list(PREPEND CMAKE_PREFIX_PATH "/n/home09/tkrishnan/.conan2/p/b/catch75024f1338965/p/lib/cmake/Catch2" "/n/home09/tkrishnan/.conan2/p/b/opensc20ff3cad4ee2/p/lib/cmake")
# The Conan local "generators" folder, where this toolchain is saved.
list(PREPEND CMAKE_PREFIX_PATH ${CMAKE_CURRENT_LIST_DIR} )
list(PREPEND CMAKE_PROGRAM_PATH "/n/home09/tkrishnan/.conan2/p/b/readl62f9b1b1e9381/p/bin" "/n/home09/tkrishnan/.conan2/p/b/bison69a19f915f2cd/p/bin" "/n/home09/tkrishnan/.conan2/p/m43fe61932e2887/p/bin")
list(PREPEND CMAKE_LIBRARY_PATH "/n/home09/tkrishnan/.conan2/p/b/catch75024f1338965/p/lib" "/n/home09/tkrishnan/.conan2/p/b/yaml-b19f5cb365505/p/lib" "/n/home09/tkrishnan/.conan2/p/b/arrowfcac7a8783ef9/p/lib" "/n/home09/tkrishnan/.conan2/p/b/thrif796e2a3f6ebfa/p/lib" "/n/home09/tkrishnan/.conan2/p/b/libev41e98abc5ae7f/p/lib" "/n/home09/tkrishnan/.conan2/p/b/opensc20ff3cad4ee2/p/lib" "/n/home09/tkrishnan/.conan2/p/b/lz414b3da346b6ce/p/lib" "/n/home09/tkrishnan/.conan2/p/b/re27cd2c5152c766/p/lib" "/n/home09/tkrishnan/.conan2/p/b/propob98fb6787c909/p/lib" "/n/home09/tkrishnan/.conan2/p/b/cubic230072d115bcf/p/lib" "/n/home09/tkrishnan/.conan2/p/b/boost439754c02dfe1/p/lib" "/n/home09/tkrishnan/.conan2/p/b/zlib405d87de74596/p/lib" "/n/home09/tkrishnan/.conan2/p/b/bzip286e47bada02be/p/lib" "/n/home09/tkrishnan/.conan2/p/b/spdlo834c9c5d7273c/p/lib" "/n/home09/tkrishnan/.conan2/p/b/fmtb702033caf202/p/lib")
list(PREPEND CMAKE_INCLUDE_PATH "/n/home09/tkrishnan/.conan2/p/b/catch75024f1338965/p/include" "/n/home09/tkrishnan/.conan2/p/b/yaml-b19f5cb365505/p/include" "/n/home09/tkrishnan/.conan2/p/cli11f6338b3142f74/p/include" "/n/home09/tkrishnan/.conan2/p/b/arrowfcac7a8783ef9/p/include" "/n/home09/tkrishnan/.conan2/p/b/thrif796e2a3f6ebfa/p/include" "/n/home09/tkrishnan/.conan2/p/b/libev41e98abc5ae7f/p/include" "/n/home09/tkrishnan/.conan2/p/b/opensc20ff3cad4ee2/p/include" "/n/home09/tkrishnan/.conan2/p/b/lz414b3da346b6ce/p/include" "/n/home09/tkrishnan/.conan2/p/xsimd1ca23010ddae9/p/include" "/n/home09/tkrishnan/.conan2/p/b/re27cd2c5152c766/p/include" "/n/home09/tkrishnan/.conan2/p/b/propob98fb6787c909/p/include" "/n/home09/tkrishnan/.conan2/p/b/cubic230072d115bcf/p/include" "/n/home09/tkrishnan/.conan2/p/b/boost439754c02dfe1/p/include" "/n/home09/tkrishnan/.conan2/p/b/zlib405d87de74596/p/include" "/n/home09/tkrishnan/.conan2/p/b/bzip286e47bada02be/p/include" "/n/home09/tkrishnan/.conan2/p/eigen5481853932f72/p/include/eigen3" "/n/home09/tkrishnan/.conan2/p/b/spdlo834c9c5d7273c/p/include" "/n/home09/tkrishnan/.conan2/p/b/fmtb702033caf202/p/include" "/n/home09/tkrishnan/.conan2/p/nlohm1bed1ddc0a2fa/p/include")
set(CONAN_RUNTIME_LIB_DIRS "/n/home09/tkrishnan/.conan2/p/b/catch75024f1338965/p/lib" "/n/home09/tkrishnan/.conan2/p/b/yaml-b19f5cb365505/p/lib" "/n/home09/tkrishnan/.conan2/p/b/arrowfcac7a8783ef9/p/lib" "/n/home09/tkrishnan/.conan2/p/b/thrif796e2a3f6ebfa/p/lib" "/n/home09/tkrishnan/.conan2/p/b/libev41e98abc5ae7f/p/lib" "/n/home09/tkrishnan/.conan2/p/b/opensc20ff3cad4ee2/p/lib" "/n/home09/tkrishnan/.conan2/p/b/lz414b3da346b6ce/p/lib" "/n/home09/tkrishnan/.conan2/p/b/re27cd2c5152c766/p/lib" "/n/home09/tkrishnan/.conan2/p/b/propob98fb6787c909/p/lib" "/n/home09/tkrishnan/.conan2/p/b/cubic230072d115bcf/p/lib" "/n/home09/tkrishnan/.conan2/p/b/boost439754c02dfe1/p/lib" "/n/home09/tkrishnan/.conan2/p/b/zlib405d87de74596/p/lib" "/n/home09/tkrishnan/.conan2/p/b/bzip286e47bada02be/p/lib" "/n/home09/tkrishnan/.conan2/p/b/spdlo834c9c5d7273c/p/lib" "/n/home09/tkrishnan/.conan2/p/b/fmtb702033caf202/p/lib" )



if (DEFINED ENV{PKG_CONFIG_PATH})
set(ENV{PKG_CONFIG_PATH} "${CMAKE_CURRENT_LIST_DIR}:$ENV{PKG_CONFIG_PATH}")
else()
set(ENV{PKG_CONFIG_PATH} "${CMAKE_CURRENT_LIST_DIR}:")
endif()




set(CMAKE_INSTALL_BINDIR "bin")
set(CMAKE_INSTALL_SBINDIR "bin")
set(CMAKE_INSTALL_LIBEXECDIR "bin")
set(CMAKE_INSTALL_LIBDIR "lib")
set(CMAKE_INSTALL_INCLUDEDIR "include")
set(CMAKE_INSTALL_OLDINCLUDEDIR "include")


# Variables
# Variables  per configuration


# Preprocessor definitions
# Preprocessor definitions per configuration


if(CMAKE_POLICY_DEFAULT_CMP0091)  # Avoid unused and not-initialized warnings
endif()
