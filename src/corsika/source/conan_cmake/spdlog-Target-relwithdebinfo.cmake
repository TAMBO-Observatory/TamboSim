# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(spdlog_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(spdlog_FRAMEWORKS_FOUND_RELWITHDEBINFO "${spdlog_FRAMEWORKS_RELWITHDEBINFO}" "${spdlog_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(spdlog_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET spdlog_DEPS_TARGET)
    add_library(spdlog_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET spdlog_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${spdlog_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${spdlog_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:fmt::fmt>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### spdlog_DEPS_TARGET to all of them
conan_package_library_targets("${spdlog_LIBS_RELWITHDEBINFO}"    # libraries
                              "${spdlog_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${spdlog_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${spdlog_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${spdlog_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              spdlog_DEPS_TARGET
                              spdlog_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "spdlog"    # package_name
                              "${spdlog_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${spdlog_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES RelWithDebInfo ########################################

    ########## COMPONENT spdlog::spdlog #############

        set(spdlog_spdlog_spdlog_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(spdlog_spdlog_spdlog_FRAMEWORKS_FOUND_RELWITHDEBINFO "${spdlog_spdlog_spdlog_FRAMEWORKS_RELWITHDEBINFO}" "${spdlog_spdlog_spdlog_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(spdlog_spdlog_spdlog_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET spdlog_spdlog_spdlog_DEPS_TARGET)
            add_library(spdlog_spdlog_spdlog_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET spdlog_spdlog_spdlog_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'spdlog_spdlog_spdlog_DEPS_TARGET' to all of them
        conan_package_library_targets("${spdlog_spdlog_spdlog_LIBS_RELWITHDEBINFO}"
                              "${spdlog_spdlog_spdlog_LIB_DIRS_RELWITHDEBINFO}"
                              "${spdlog_spdlog_spdlog_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${spdlog_spdlog_spdlog_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${spdlog_spdlog_spdlog_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              spdlog_spdlog_spdlog_DEPS_TARGET
                              spdlog_spdlog_spdlog_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "spdlog_spdlog_spdlog"
                              "${spdlog_spdlog_spdlog_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET spdlog::spdlog
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_LIBRARIES_TARGETS}>
                     )

        if("${spdlog_spdlog_spdlog_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET spdlog::spdlog
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         spdlog_spdlog_spdlog_DEPS_TARGET)
        endif()

        set_property(TARGET spdlog::spdlog APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET spdlog::spdlog APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET spdlog::spdlog APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET spdlog::spdlog APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET spdlog::spdlog APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${spdlog_spdlog_spdlog_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET spdlog::spdlog APPEND PROPERTY INTERFACE_LINK_LIBRARIES spdlog::spdlog)

########## For the modules (FindXXX)
set(spdlog_LIBRARIES_RELWITHDEBINFO spdlog::spdlog)
