# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(arrow_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(arrow_FRAMEWORKS_FOUND_RELWITHDEBINFO "${arrow_FRAMEWORKS_RELWITHDEBINFO}" "${arrow_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(arrow_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET arrow_DEPS_TARGET)
    add_library(arrow_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET arrow_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${arrow_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${arrow_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:boost::boost;re2::re2;thrift::thrift-conan-do-not-use;LZ4::lz4_static;ZLIB::ZLIB;Arrow::arrow_static>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### arrow_DEPS_TARGET to all of them
conan_package_library_targets("${arrow_LIBS_RELWITHDEBINFO}"    # libraries
                              "${arrow_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${arrow_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${arrow_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${arrow_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              arrow_DEPS_TARGET
                              arrow_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "arrow"    # package_name
                              "${arrow_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${arrow_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES RelWithDebInfo ########################################

    ########## COMPONENT Parquet::parquet_static #############

        set(arrow_Parquet_parquet_static_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(arrow_Parquet_parquet_static_FRAMEWORKS_FOUND_RELWITHDEBINFO "${arrow_Parquet_parquet_static_FRAMEWORKS_RELWITHDEBINFO}" "${arrow_Parquet_parquet_static_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(arrow_Parquet_parquet_static_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET arrow_Parquet_parquet_static_DEPS_TARGET)
            add_library(arrow_Parquet_parquet_static_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET arrow_Parquet_parquet_static_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'arrow_Parquet_parquet_static_DEPS_TARGET' to all of them
        conan_package_library_targets("${arrow_Parquet_parquet_static_LIBS_RELWITHDEBINFO}"
                              "${arrow_Parquet_parquet_static_LIB_DIRS_RELWITHDEBINFO}"
                              "${arrow_Parquet_parquet_static_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${arrow_Parquet_parquet_static_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${arrow_Parquet_parquet_static_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              arrow_Parquet_parquet_static_DEPS_TARGET
                              arrow_Parquet_parquet_static_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "arrow_Parquet_parquet_static"
                              "${arrow_Parquet_parquet_static_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Parquet::parquet_static
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_LIBRARIES_TARGETS}>
                     )

        if("${arrow_Parquet_parquet_static_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Parquet::parquet_static
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         arrow_Parquet_parquet_static_DEPS_TARGET)
        endif()

        set_property(TARGET Parquet::parquet_static APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Parquet::parquet_static APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Parquet::parquet_static APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Parquet::parquet_static APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Parquet::parquet_static APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Parquet_parquet_static_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT Arrow::arrow_static #############

        set(arrow_Arrow_arrow_static_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(arrow_Arrow_arrow_static_FRAMEWORKS_FOUND_RELWITHDEBINFO "${arrow_Arrow_arrow_static_FRAMEWORKS_RELWITHDEBINFO}" "${arrow_Arrow_arrow_static_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(arrow_Arrow_arrow_static_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET arrow_Arrow_arrow_static_DEPS_TARGET)
            add_library(arrow_Arrow_arrow_static_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET arrow_Arrow_arrow_static_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'arrow_Arrow_arrow_static_DEPS_TARGET' to all of them
        conan_package_library_targets("${arrow_Arrow_arrow_static_LIBS_RELWITHDEBINFO}"
                              "${arrow_Arrow_arrow_static_LIB_DIRS_RELWITHDEBINFO}"
                              "${arrow_Arrow_arrow_static_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${arrow_Arrow_arrow_static_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${arrow_Arrow_arrow_static_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              arrow_Arrow_arrow_static_DEPS_TARGET
                              arrow_Arrow_arrow_static_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "arrow_Arrow_arrow_static"
                              "${arrow_Arrow_arrow_static_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET Arrow::arrow_static
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_LIBRARIES_TARGETS}>
                     )

        if("${arrow_Arrow_arrow_static_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET Arrow::arrow_static
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         arrow_Arrow_arrow_static_DEPS_TARGET)
        endif()

        set_property(TARGET Arrow::arrow_static APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET Arrow::arrow_static APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Arrow::arrow_static APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET Arrow::arrow_static APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET Arrow::arrow_static APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${arrow_Arrow_arrow_static_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET arrow::arrow APPEND PROPERTY INTERFACE_LINK_LIBRARIES Parquet::parquet_static)
    set_property(TARGET arrow::arrow APPEND PROPERTY INTERFACE_LINK_LIBRARIES Arrow::arrow_static)

########## For the modules (FindXXX)
set(arrow_LIBRARIES_RELWITHDEBINFO arrow::arrow)
