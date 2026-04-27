# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(cubicinterpolation_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(cubicinterpolation_FRAMEWORKS_FOUND_RELWITHDEBINFO "${cubicinterpolation_FRAMEWORKS_RELWITHDEBINFO}" "${cubicinterpolation_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(cubicinterpolation_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET cubicinterpolation_DEPS_TARGET)
    add_library(cubicinterpolation_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET cubicinterpolation_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:Boost::headers;Boost::filesystem;Boost::math;Boost::serialization;Eigen3::Eigen>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### cubicinterpolation_DEPS_TARGET to all of them
conan_package_library_targets("${cubicinterpolation_LIBS_RELWITHDEBINFO}"    # libraries
                              "${cubicinterpolation_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${cubicinterpolation_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${cubicinterpolation_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${cubicinterpolation_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              cubicinterpolation_DEPS_TARGET
                              cubicinterpolation_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "cubicinterpolation"    # package_name
                              "${cubicinterpolation_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${cubicinterpolation_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES RelWithDebInfo ########################################
    set_property(TARGET CubicInterpolation::CubicInterpolation
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_OBJECTS_RELWITHDEBINFO}>
                 $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_LIBRARIES_TARGETS}>
                 )

    if("${cubicinterpolation_LIBS_RELWITHDEBINFO}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET CubicInterpolation::CubicInterpolation
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     cubicinterpolation_DEPS_TARGET)
    endif()

    set_property(TARGET CubicInterpolation::CubicInterpolation
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_LINKER_FLAGS_RELWITHDEBINFO}>)
    set_property(TARGET CubicInterpolation::CubicInterpolation
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_INCLUDE_DIRS_RELWITHDEBINFO}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET CubicInterpolation::CubicInterpolation
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_LIB_DIRS_RELWITHDEBINFO}>)
    set_property(TARGET CubicInterpolation::CubicInterpolation
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
    set_property(TARGET CubicInterpolation::CubicInterpolation
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:RelWithDebInfo>:${cubicinterpolation_COMPILE_OPTIONS_RELWITHDEBINFO}>)

########## For the modules (FindXXX)
set(cubicinterpolation_LIBRARIES_RELWITHDEBINFO CubicInterpolation::CubicInterpolation)
