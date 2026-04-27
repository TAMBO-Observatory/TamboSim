########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(Thrift_FIND_QUIETLY)
    set(Thrift_MESSAGE_MODE VERBOSE)
else()
    set(Thrift_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/ThriftTargets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${thrift_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(Thrift_VERSION_STRING "0.20.0")
set(Thrift_INCLUDE_DIRS ${thrift_INCLUDE_DIRS_RELWITHDEBINFO} )
set(Thrift_INCLUDE_DIR ${thrift_INCLUDE_DIRS_RELWITHDEBINFO} )
set(Thrift_LIBRARIES ${thrift_LIBRARIES_RELWITHDEBINFO} )
set(Thrift_DEFINITIONS ${thrift_DEFINITIONS_RELWITHDEBINFO} )


# Only the last installed configuration BUILD_MODULES are included to avoid the collision
foreach(_BUILD_MODULE ${thrift_BUILD_MODULES_PATHS_RELWITHDEBINFO} )
    message(${Thrift_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


