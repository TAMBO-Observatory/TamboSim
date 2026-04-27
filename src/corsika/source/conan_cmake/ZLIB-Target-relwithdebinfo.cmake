# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(zlib_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(zlib_FRAMEWORKS_FOUND_RELWITHDEBINFO "${zlib_FRAMEWORKS_RELWITHDEBINFO}" "${zlib_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(zlib_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET zlib_DEPS_TARGET)
    add_library(zlib_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET zlib_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${zlib_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${zlib_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### zlib_DEPS_TARGET to all of them
conan_package_library_targets("${zlib_LIBS_RELWITHDEBINFO}"    # libraries
                              "${zlib_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${zlib_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${zlib_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${zlib_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              zlib_DEPS_TARGET
                              zlib_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "zlib"    # package_name
                              "${zlib_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${zlib_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES RelWithDebInfo ########################################
    set_property(TARGET ZLIB::ZLIB
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:RelWithDebInfo>:${zlib_OBJECTS_RELWITHDEBINFO}>
                 $<$<CONFIG:RelWithDebInfo>:${zlib_LIBRARIES_TARGETS}>
                 )

    if("${zlib_LIBS_RELWITHDEBINFO}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET ZLIB::ZLIB
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     zlib_DEPS_TARGET)
    endif()

    set_property(TARGET ZLIB::ZLIB
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:RelWithDebInfo>:${zlib_LINKER_FLAGS_RELWITHDEBINFO}>)
    set_property(TARGET ZLIB::ZLIB
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:RelWithDebInfo>:${zlib_INCLUDE_DIRS_RELWITHDEBINFO}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET ZLIB::ZLIB
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:RelWithDebInfo>:${zlib_LIB_DIRS_RELWITHDEBINFO}>)
    set_property(TARGET ZLIB::ZLIB
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:RelWithDebInfo>:${zlib_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
    set_property(TARGET ZLIB::ZLIB
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:RelWithDebInfo>:${zlib_COMPILE_OPTIONS_RELWITHDEBINFO}>)

########## For the modules (FindXXX)
set(zlib_LIBRARIES_RELWITHDEBINFO ZLIB::ZLIB)
