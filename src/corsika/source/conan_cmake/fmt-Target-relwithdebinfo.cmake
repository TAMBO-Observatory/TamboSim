# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(fmt_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(fmt_FRAMEWORKS_FOUND_RELWITHDEBINFO "${fmt_FRAMEWORKS_RELWITHDEBINFO}" "${fmt_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(fmt_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET fmt_DEPS_TARGET)
    add_library(fmt_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET fmt_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${fmt_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${fmt_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### fmt_DEPS_TARGET to all of them
conan_package_library_targets("${fmt_LIBS_RELWITHDEBINFO}"    # libraries
                              "${fmt_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${fmt_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${fmt_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${fmt_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              fmt_DEPS_TARGET
                              fmt_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "fmt"    # package_name
                              "${fmt_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${fmt_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES RelWithDebInfo ########################################

    ########## COMPONENT fmt::fmt #############

        set(fmt_fmt_fmt_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(fmt_fmt_fmt_FRAMEWORKS_FOUND_RELWITHDEBINFO "${fmt_fmt_fmt_FRAMEWORKS_RELWITHDEBINFO}" "${fmt_fmt_fmt_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(fmt_fmt_fmt_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET fmt_fmt_fmt_DEPS_TARGET)
            add_library(fmt_fmt_fmt_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET fmt_fmt_fmt_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'fmt_fmt_fmt_DEPS_TARGET' to all of them
        conan_package_library_targets("${fmt_fmt_fmt_LIBS_RELWITHDEBINFO}"
                              "${fmt_fmt_fmt_LIB_DIRS_RELWITHDEBINFO}"
                              "${fmt_fmt_fmt_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${fmt_fmt_fmt_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${fmt_fmt_fmt_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              fmt_fmt_fmt_DEPS_TARGET
                              fmt_fmt_fmt_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "fmt_fmt_fmt"
                              "${fmt_fmt_fmt_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET fmt::fmt
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_LIBRARIES_TARGETS}>
                     )

        if("${fmt_fmt_fmt_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET fmt::fmt
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         fmt_fmt_fmt_DEPS_TARGET)
        endif()

        set_property(TARGET fmt::fmt APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET fmt::fmt APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET fmt::fmt APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET fmt::fmt APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET fmt::fmt APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${fmt_fmt_fmt_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET fmt::fmt APPEND PROPERTY INTERFACE_LINK_LIBRARIES fmt::fmt)

########## For the modules (FindXXX)
set(fmt_LIBRARIES_RELWITHDEBINFO fmt::fmt)
