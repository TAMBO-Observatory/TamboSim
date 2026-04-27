########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(CubicInterpolation_FIND_QUIETLY)
    set(CubicInterpolation_MESSAGE_MODE VERBOSE)
else()
    set(CubicInterpolation_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/CubicInterpolationTargets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${cubicinterpolation_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(CubicInterpolation_VERSION_STRING "0.1.5")
set(CubicInterpolation_INCLUDE_DIRS ${cubicinterpolation_INCLUDE_DIRS_RELWITHDEBINFO} )
set(CubicInterpolation_INCLUDE_DIR ${cubicinterpolation_INCLUDE_DIRS_RELWITHDEBINFO} )
set(CubicInterpolation_LIBRARIES ${cubicinterpolation_LIBRARIES_RELWITHDEBINFO} )
set(CubicInterpolation_DEFINITIONS ${cubicinterpolation_DEFINITIONS_RELWITHDEBINFO} )


# Only the last installed configuration BUILD_MODULES are included to avoid the collision
foreach(_BUILD_MODULE ${cubicinterpolation_BUILD_MODULES_PATHS_RELWITHDEBINFO} )
    message(${CubicInterpolation_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


