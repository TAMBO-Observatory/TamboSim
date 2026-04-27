########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(Eigen3_FIND_QUIETLY)
    set(Eigen3_MESSAGE_MODE VERBOSE)
else()
    set(Eigen3_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/Eigen3Targets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${eigen_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(Eigen3_VERSION_STRING "3.4.0")
set(Eigen3_INCLUDE_DIRS ${eigen_INCLUDE_DIRS_RELWITHDEBINFO} )
set(Eigen3_INCLUDE_DIR ${eigen_INCLUDE_DIRS_RELWITHDEBINFO} )
set(Eigen3_LIBRARIES ${eigen_LIBRARIES_RELWITHDEBINFO} )
set(Eigen3_DEFINITIONS ${eigen_DEFINITIONS_RELWITHDEBINFO} )


# Only the last installed configuration BUILD_MODULES are included to avoid the collision
foreach(_BUILD_MODULE ${eigen_BUILD_MODULES_PATHS_RELWITHDEBINFO} )
    message(${Eigen3_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


