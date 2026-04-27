########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(PROPOSAL_FIND_QUIETLY)
    set(PROPOSAL_MESSAGE_MODE VERBOSE)
else()
    set(PROPOSAL_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/PROPOSALTargets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${proposal_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(PROPOSAL_VERSION_STRING "7.6.2")
set(PROPOSAL_INCLUDE_DIRS ${proposal_INCLUDE_DIRS_RELWITHDEBINFO} )
set(PROPOSAL_INCLUDE_DIR ${proposal_INCLUDE_DIRS_RELWITHDEBINFO} )
set(PROPOSAL_LIBRARIES ${proposal_LIBRARIES_RELWITHDEBINFO} )
set(PROPOSAL_DEFINITIONS ${proposal_DEFINITIONS_RELWITHDEBINFO} )


# Only the last installed configuration BUILD_MODULES are included to avoid the collision
foreach(_BUILD_MODULE ${proposal_BUILD_MODULES_PATHS_RELWITHDEBINFO} )
    message(${PROPOSAL_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


