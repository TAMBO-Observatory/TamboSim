# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(yaml-cpp_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(yaml-cpp_FRAMEWORKS_FOUND_RELWITHDEBINFO "${yaml-cpp_FRAMEWORKS_RELWITHDEBINFO}" "${yaml-cpp_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(yaml-cpp_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET yaml-cpp_DEPS_TARGET)
    add_library(yaml-cpp_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET yaml-cpp_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### yaml-cpp_DEPS_TARGET to all of them
conan_package_library_targets("${yaml-cpp_LIBS_RELWITHDEBINFO}"    # libraries
                              "${yaml-cpp_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${yaml-cpp_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${yaml-cpp_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${yaml-cpp_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              yaml-cpp_DEPS_TARGET
                              yaml-cpp_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "yaml-cpp"    # package_name
                              "${yaml-cpp_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${yaml-cpp_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES RelWithDebInfo ########################################
    set_property(TARGET yaml-cpp::yaml-cpp
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_OBJECTS_RELWITHDEBINFO}>
                 $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_LIBRARIES_TARGETS}>
                 )

    if("${yaml-cpp_LIBS_RELWITHDEBINFO}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET yaml-cpp::yaml-cpp
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     yaml-cpp_DEPS_TARGET)
    endif()

    set_property(TARGET yaml-cpp::yaml-cpp
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_LINKER_FLAGS_RELWITHDEBINFO}>)
    set_property(TARGET yaml-cpp::yaml-cpp
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_INCLUDE_DIRS_RELWITHDEBINFO}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET yaml-cpp::yaml-cpp
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_LIB_DIRS_RELWITHDEBINFO}>)
    set_property(TARGET yaml-cpp::yaml-cpp
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
    set_property(TARGET yaml-cpp::yaml-cpp
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:RelWithDebInfo>:${yaml-cpp_COMPILE_OPTIONS_RELWITHDEBINFO}>)

########## For the modules (FindXXX)
set(yaml-cpp_LIBRARIES_RELWITHDEBINFO yaml-cpp::yaml-cpp)
