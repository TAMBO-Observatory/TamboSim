########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(CLI11_FIND_QUIETLY)
    set(CLI11_MESSAGE_MODE VERBOSE)
else()
    set(CLI11_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/CLI11Targets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${cli11_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(CLI11_VERSION_STRING "1.9.1")
set(CLI11_INCLUDE_DIRS ${cli11_INCLUDE_DIRS_RELWITHDEBINFO} )
set(CLI11_INCLUDE_DIR ${cli11_INCLUDE_DIRS_RELWITHDEBINFO} )
set(CLI11_LIBRARIES ${cli11_LIBRARIES_RELWITHDEBINFO} )
set(CLI11_DEFINITIONS ${cli11_DEFINITIONS_RELWITHDEBINFO} )


# Only the last installed configuration BUILD_MODULES are included to avoid the collision
foreach(_BUILD_MODULE ${cli11_BUILD_MODULES_PATHS_RELWITHDEBINFO} )
    message(${CLI11_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


