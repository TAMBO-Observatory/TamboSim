# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(proposal_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(proposal_FRAMEWORKS_FOUND_RELWITHDEBINFO "${proposal_FRAMEWORKS_RELWITHDEBINFO}" "${proposal_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(proposal_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET proposal_DEPS_TARGET)
    add_library(proposal_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET proposal_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${proposal_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${proposal_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:CubicInterpolation::CubicInterpolation;spdlog::spdlog;nlohmann_json::nlohmann_json>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### proposal_DEPS_TARGET to all of them
conan_package_library_targets("${proposal_LIBS_RELWITHDEBINFO}"    # libraries
                              "${proposal_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${proposal_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${proposal_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${proposal_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              proposal_DEPS_TARGET
                              proposal_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "proposal"    # package_name
                              "${proposal_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${proposal_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES RelWithDebInfo ########################################
    set_property(TARGET PROPOSAL::PROPOSAL
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:RelWithDebInfo>:${proposal_OBJECTS_RELWITHDEBINFO}>
                 $<$<CONFIG:RelWithDebInfo>:${proposal_LIBRARIES_TARGETS}>
                 )

    if("${proposal_LIBS_RELWITHDEBINFO}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET PROPOSAL::PROPOSAL
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     proposal_DEPS_TARGET)
    endif()

    set_property(TARGET PROPOSAL::PROPOSAL
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:RelWithDebInfo>:${proposal_LINKER_FLAGS_RELWITHDEBINFO}>)
    set_property(TARGET PROPOSAL::PROPOSAL
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:RelWithDebInfo>:${proposal_INCLUDE_DIRS_RELWITHDEBINFO}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET PROPOSAL::PROPOSAL
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:RelWithDebInfo>:${proposal_LIB_DIRS_RELWITHDEBINFO}>)
    set_property(TARGET PROPOSAL::PROPOSAL
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:RelWithDebInfo>:${proposal_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
    set_property(TARGET PROPOSAL::PROPOSAL
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:RelWithDebInfo>:${proposal_COMPILE_OPTIONS_RELWITHDEBINFO}>)

########## For the modules (FindXXX)
set(proposal_LIBRARIES_RELWITHDEBINFO PROPOSAL::PROPOSAL)
