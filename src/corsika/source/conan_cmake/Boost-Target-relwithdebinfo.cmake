# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(boost_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(boost_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_FRAMEWORKS_RELWITHDEBINFO}" "${boost_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(boost_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET boost_DEPS_TARGET)
    add_library(boost_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET boost_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${boost_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${boost_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:Boost::diagnostic_definitions;Boost::disable_autolinking;Boost::dynamic_linking;Boost::headers;boost::_libboost;Boost::system;Boost::atomic;Boost::random;Boost::regex;BZip2::BZip2;ZLIB::ZLIB;Boost::math;Boost::serialization>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### boost_DEPS_TARGET to all of them
conan_package_library_targets("${boost_LIBS_RELWITHDEBINFO}"    # libraries
                              "${boost_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${boost_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_DEPS_TARGET
                              boost_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "boost"    # package_name
                              "${boost_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${boost_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES RelWithDebInfo ########################################

    ########## COMPONENT Boost::iostreams #############

        set(boost_Boost_iostreams_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_iostreams_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_iostreams_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_iostreams_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_iostreams_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_iostreams_DEPS_TARGET)
            add_library(boost_Boost_iostreams_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_iostreams_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_iostreams_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_iostreams_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_iostreams_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_iostreams_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_iostreams_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_iostreams_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_iostreams_DEPS_TARGET
                              boost_Boost_iostreams_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_iostreams"
                              "${boost_Boost_iostreams_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::iostreams
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_iostreams_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::iostreams
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_iostreams_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::iostreams APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::iostreams APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::iostreams APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::iostreams APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::iostreams APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_iostreams_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::random #############

        set(boost_Boost_random_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_random_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_random_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_random_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_random_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_random_DEPS_TARGET)
            add_library(boost_Boost_random_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_random_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_random_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_random_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_random_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_random_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_random_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_random_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_random_DEPS_TARGET
                              boost_Boost_random_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_random"
                              "${boost_Boost_random_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::random
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_random_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::random
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_random_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::random APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::random APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::random APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::random APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::random APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_random_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::filesystem #############

        set(boost_Boost_filesystem_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_filesystem_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_filesystem_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_filesystem_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_filesystem_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_filesystem_DEPS_TARGET)
            add_library(boost_Boost_filesystem_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_filesystem_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_filesystem_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_filesystem_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_filesystem_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_filesystem_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_filesystem_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_filesystem_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_filesystem_DEPS_TARGET
                              boost_Boost_filesystem_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_filesystem"
                              "${boost_Boost_filesystem_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::filesystem
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_filesystem_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::filesystem
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_filesystem_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::filesystem APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::filesystem APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::filesystem APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::filesystem APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::filesystem APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_filesystem_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::chrono #############

        set(boost_Boost_chrono_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_chrono_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_chrono_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_chrono_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_chrono_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_chrono_DEPS_TARGET)
            add_library(boost_Boost_chrono_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_chrono_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_chrono_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_chrono_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_chrono_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_chrono_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_chrono_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_chrono_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_chrono_DEPS_TARGET
                              boost_Boost_chrono_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_chrono"
                              "${boost_Boost_chrono_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::chrono
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_chrono_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::chrono
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_chrono_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::chrono APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::chrono APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::chrono APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::chrono APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::chrono APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_chrono_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::wserialization #############

        set(boost_Boost_wserialization_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_wserialization_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_wserialization_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_wserialization_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_wserialization_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_wserialization_DEPS_TARGET)
            add_library(boost_Boost_wserialization_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_wserialization_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_wserialization_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_wserialization_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_wserialization_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_wserialization_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_wserialization_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_wserialization_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_wserialization_DEPS_TARGET
                              boost_Boost_wserialization_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_wserialization"
                              "${boost_Boost_wserialization_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::wserialization
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_wserialization_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::wserialization
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_wserialization_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::wserialization APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::wserialization APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::wserialization APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::wserialization APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::wserialization APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_wserialization_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::url #############

        set(boost_Boost_url_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_url_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_url_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_url_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_url_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_url_DEPS_TARGET)
            add_library(boost_Boost_url_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_url_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_url_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_url_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_url_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_url_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_url_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_url_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_url_DEPS_TARGET
                              boost_Boost_url_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_url"
                              "${boost_Boost_url_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::url
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_url_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::url
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_url_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::url APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::url APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::url APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::url APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::url APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_url_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::system #############

        set(boost_Boost_system_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_system_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_system_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_system_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_system_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_system_DEPS_TARGET)
            add_library(boost_Boost_system_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_system_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_system_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_system_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_system_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_system_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_system_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_system_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_system_DEPS_TARGET
                              boost_Boost_system_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_system"
                              "${boost_Boost_system_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::system
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_system_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::system
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_system_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::system APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::system APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::system APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::system APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::system APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_system_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::serialization #############

        set(boost_Boost_serialization_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_serialization_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_serialization_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_serialization_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_serialization_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_serialization_DEPS_TARGET)
            add_library(boost_Boost_serialization_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_serialization_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_serialization_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_serialization_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_serialization_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_serialization_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_serialization_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_serialization_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_serialization_DEPS_TARGET
                              boost_Boost_serialization_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_serialization"
                              "${boost_Boost_serialization_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::serialization
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_serialization_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::serialization
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_serialization_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::serialization APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::serialization APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::serialization APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::serialization APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::serialization APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_serialization_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::regex #############

        set(boost_Boost_regex_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_regex_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_regex_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_regex_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_regex_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_regex_DEPS_TARGET)
            add_library(boost_Boost_regex_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_regex_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_regex_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_regex_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_regex_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_regex_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_regex_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_regex_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_regex_DEPS_TARGET
                              boost_Boost_regex_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_regex"
                              "${boost_Boost_regex_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::regex
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_regex_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::regex
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_regex_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::regex APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::regex APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::regex APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::regex APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::regex APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_regex_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::math_tr1l #############

        set(boost_Boost_math_tr1l_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_math_tr1l_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_math_tr1l_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_math_tr1l_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_math_tr1l_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_math_tr1l_DEPS_TARGET)
            add_library(boost_Boost_math_tr1l_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_math_tr1l_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_math_tr1l_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_math_tr1l_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1l_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1l_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_math_tr1l_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1l_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_math_tr1l_DEPS_TARGET
                              boost_Boost_math_tr1l_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_math_tr1l"
                              "${boost_Boost_math_tr1l_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::math_tr1l
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_math_tr1l_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::math_tr1l
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_math_tr1l_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::math_tr1l APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1l APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1l APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1l APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1l APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1l_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::math_tr1f #############

        set(boost_Boost_math_tr1f_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_math_tr1f_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_math_tr1f_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_math_tr1f_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_math_tr1f_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_math_tr1f_DEPS_TARGET)
            add_library(boost_Boost_math_tr1f_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_math_tr1f_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_math_tr1f_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_math_tr1f_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1f_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1f_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_math_tr1f_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1f_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_math_tr1f_DEPS_TARGET
                              boost_Boost_math_tr1f_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_math_tr1f"
                              "${boost_Boost_math_tr1f_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::math_tr1f
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_math_tr1f_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::math_tr1f
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_math_tr1f_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::math_tr1f APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1f APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1f APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1f APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1f APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1f_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::math_tr1 #############

        set(boost_Boost_math_tr1_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_math_tr1_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_math_tr1_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_math_tr1_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_math_tr1_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_math_tr1_DEPS_TARGET)
            add_library(boost_Boost_math_tr1_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_math_tr1_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_math_tr1_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_math_tr1_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_math_tr1_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_math_tr1_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_math_tr1_DEPS_TARGET
                              boost_Boost_math_tr1_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_math_tr1"
                              "${boost_Boost_math_tr1_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::math_tr1
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_math_tr1_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::math_tr1
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_math_tr1_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::math_tr1 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_tr1 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_tr1_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::math_c99l #############

        set(boost_Boost_math_c99l_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_math_c99l_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_math_c99l_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_math_c99l_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_math_c99l_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_math_c99l_DEPS_TARGET)
            add_library(boost_Boost_math_c99l_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_math_c99l_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_math_c99l_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_math_c99l_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99l_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99l_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_math_c99l_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99l_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_math_c99l_DEPS_TARGET
                              boost_Boost_math_c99l_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_math_c99l"
                              "${boost_Boost_math_c99l_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::math_c99l
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_math_c99l_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::math_c99l
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_math_c99l_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::math_c99l APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99l APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99l APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99l APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99l APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99l_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::math_c99f #############

        set(boost_Boost_math_c99f_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_math_c99f_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_math_c99f_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_math_c99f_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_math_c99f_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_math_c99f_DEPS_TARGET)
            add_library(boost_Boost_math_c99f_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_math_c99f_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_math_c99f_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_math_c99f_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99f_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99f_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_math_c99f_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99f_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_math_c99f_DEPS_TARGET
                              boost_Boost_math_c99f_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_math_c99f"
                              "${boost_Boost_math_c99f_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::math_c99f
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_math_c99f_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::math_c99f
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_math_c99f_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::math_c99f APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99f APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99f APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99f APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99f APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99f_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::math_c99 #############

        set(boost_Boost_math_c99_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_math_c99_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_math_c99_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_math_c99_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_math_c99_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_math_c99_DEPS_TARGET)
            add_library(boost_Boost_math_c99_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_math_c99_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_math_c99_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_math_c99_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_math_c99_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_math_c99_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_math_c99_DEPS_TARGET
                              boost_Boost_math_c99_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_math_c99"
                              "${boost_Boost_math_c99_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::math_c99
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_math_c99_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::math_c99
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_math_c99_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::math_c99 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math_c99 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_c99_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::math #############

        set(boost_Boost_math_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_math_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_math_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_math_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_math_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_math_DEPS_TARGET)
            add_library(boost_Boost_math_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_math_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_math_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_math_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_math_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_math_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_math_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_math_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_math_DEPS_TARGET
                              boost_Boost_math_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_math"
                              "${boost_Boost_math_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::math
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_math_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::math
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_math_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::math APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::math APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_math_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::exception #############

        set(boost_Boost_exception_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_exception_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_exception_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_exception_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_exception_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_exception_DEPS_TARGET)
            add_library(boost_Boost_exception_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_exception_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_exception_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_exception_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_exception_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_exception_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_exception_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_exception_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_exception_DEPS_TARGET
                              boost_Boost_exception_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_exception"
                              "${boost_Boost_exception_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::exception
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_exception_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::exception
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_exception_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::exception APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::exception APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::exception APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::exception APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::exception APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_exception_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::charconv #############

        set(boost_Boost_charconv_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_charconv_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_charconv_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_charconv_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_charconv_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_charconv_DEPS_TARGET)
            add_library(boost_Boost_charconv_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_charconv_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_charconv_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_charconv_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_charconv_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_charconv_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_charconv_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_charconv_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_charconv_DEPS_TARGET
                              boost_Boost_charconv_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_charconv"
                              "${boost_Boost_charconv_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::charconv
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_charconv_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::charconv
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_charconv_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::charconv APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::charconv APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::charconv APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::charconv APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::charconv APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_charconv_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::atomic #############

        set(boost_Boost_atomic_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_atomic_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_atomic_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_atomic_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_atomic_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_atomic_DEPS_TARGET)
            add_library(boost_Boost_atomic_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_atomic_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_atomic_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_atomic_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_atomic_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_atomic_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_atomic_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_atomic_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_atomic_DEPS_TARGET
                              boost_Boost_atomic_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_atomic"
                              "${boost_Boost_atomic_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::atomic
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_atomic_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::atomic
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_atomic_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::atomic APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::atomic APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::atomic APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::atomic APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::atomic APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_atomic_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT boost::_libboost #############

        set(boost_boost__libboost_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_boost__libboost_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_boost__libboost_FRAMEWORKS_RELWITHDEBINFO}" "${boost_boost__libboost_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_boost__libboost_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_boost__libboost_DEPS_TARGET)
            add_library(boost_boost__libboost_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_boost__libboost_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_boost__libboost_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_boost__libboost_LIBS_RELWITHDEBINFO}"
                              "${boost_boost__libboost_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_boost__libboost_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_boost__libboost_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_boost__libboost_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_boost__libboost_DEPS_TARGET
                              boost_boost__libboost_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_boost__libboost"
                              "${boost_boost__libboost_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET boost::_libboost
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_LIBRARIES_TARGETS}>
                     )

        if("${boost_boost__libboost_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET boost::_libboost
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_boost__libboost_DEPS_TARGET)
        endif()

        set_property(TARGET boost::_libboost APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET boost::_libboost APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET boost::_libboost APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET boost::_libboost APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET boost::_libboost APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_boost__libboost_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::boost #############

        set(boost_Boost_boost_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_boost_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_boost_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_boost_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_boost_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_boost_DEPS_TARGET)
            add_library(boost_Boost_boost_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_boost_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_boost_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_boost_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_boost_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_boost_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_boost_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_boost_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_boost_DEPS_TARGET
                              boost_Boost_boost_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_boost"
                              "${boost_Boost_boost_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::boost
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_boost_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::boost
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_boost_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::boost APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::boost APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::boost APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::boost APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::boost APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_boost_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::headers #############

        set(boost_Boost_headers_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_headers_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_headers_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_headers_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_headers_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_headers_DEPS_TARGET)
            add_library(boost_Boost_headers_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_headers_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_headers_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_headers_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_headers_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_headers_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_headers_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_headers_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_headers_DEPS_TARGET
                              boost_Boost_headers_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_headers"
                              "${boost_Boost_headers_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::headers
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_headers_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::headers
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_headers_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::headers APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::headers APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::headers APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::headers APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::headers APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_headers_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::dynamic_linking #############

        set(boost_Boost_dynamic_linking_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_dynamic_linking_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_dynamic_linking_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_dynamic_linking_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_dynamic_linking_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_dynamic_linking_DEPS_TARGET)
            add_library(boost_Boost_dynamic_linking_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_dynamic_linking_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_dynamic_linking_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_dynamic_linking_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_dynamic_linking_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_dynamic_linking_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_dynamic_linking_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_dynamic_linking_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_dynamic_linking_DEPS_TARGET
                              boost_Boost_dynamic_linking_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_dynamic_linking"
                              "${boost_Boost_dynamic_linking_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::dynamic_linking
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_dynamic_linking_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::dynamic_linking
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_dynamic_linking_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::dynamic_linking APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::dynamic_linking APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::dynamic_linking APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::dynamic_linking APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::dynamic_linking APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_dynamic_linking_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::disable_autolinking #############

        set(boost_Boost_disable_autolinking_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_disable_autolinking_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_disable_autolinking_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_disable_autolinking_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_disable_autolinking_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_disable_autolinking_DEPS_TARGET)
            add_library(boost_Boost_disable_autolinking_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_disable_autolinking_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_disable_autolinking_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_disable_autolinking_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_disable_autolinking_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_disable_autolinking_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_disable_autolinking_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_disable_autolinking_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_disable_autolinking_DEPS_TARGET
                              boost_Boost_disable_autolinking_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_disable_autolinking"
                              "${boost_Boost_disable_autolinking_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::disable_autolinking
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_disable_autolinking_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::disable_autolinking
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_disable_autolinking_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::disable_autolinking APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::disable_autolinking APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::disable_autolinking APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::disable_autolinking APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::disable_autolinking APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_disable_autolinking_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Boost::diagnostic_definitions #############

        set(boost_Boost_diagnostic_definitions_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(boost_Boost_diagnostic_definitions_FRAMEWORKS_FOUND_RELWITHDEBINFO "${boost_Boost_diagnostic_definitions_FRAMEWORKS_RELWITHDEBINFO}" "${boost_Boost_diagnostic_definitions_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(boost_Boost_diagnostic_definitions_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET boost_Boost_diagnostic_definitions_DEPS_TARGET)
            add_library(boost_Boost_diagnostic_definitions_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET boost_Boost_diagnostic_definitions_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'boost_Boost_diagnostic_definitions_DEPS_TARGET' to all of them
        conan_package_library_targets("${boost_Boost_diagnostic_definitions_LIBS_RELWITHDEBINFO}"
                              "${boost_Boost_diagnostic_definitions_LIB_DIRS_RELWITHDEBINFO}"
                              "${boost_Boost_diagnostic_definitions_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${boost_Boost_diagnostic_definitions_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${boost_Boost_diagnostic_definitions_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              boost_Boost_diagnostic_definitions_DEPS_TARGET
                              boost_Boost_diagnostic_definitions_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "boost_Boost_diagnostic_definitions"
                              "${boost_Boost_diagnostic_definitions_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Boost::diagnostic_definitions
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_LIBRARIES_TARGETS}>
                     )

        if("${boost_Boost_diagnostic_definitions_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Boost::diagnostic_definitions
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         boost_Boost_diagnostic_definitions_DEPS_TARGET)
        endif()

        set_property(TARGET Boost::diagnostic_definitions APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::diagnostic_definitions APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::diagnostic_definitions APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::diagnostic_definitions APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Boost::diagnostic_definitions APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${boost_Boost_diagnostic_definitions_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::iostreams)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::random)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::filesystem)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::chrono)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::wserialization)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::url)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::system)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::serialization)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::regex)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::math_tr1l)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::math_tr1f)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::math_tr1)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::math_c99l)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::math_c99f)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::math_c99)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::math)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::exception)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::charconv)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::atomic)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES boost::_libboost)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::boost)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::headers)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::dynamic_linking)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::disable_autolinking)
    set_property(TARGET boost::boost APPEND PROPERTY INTERFACE_LINK_LIBRARIES Boost::diagnostic_definitions)

########## For the modules (FindXXX)
set(boost_LIBRARIES_RELWITHDEBINFO boost::boost)
