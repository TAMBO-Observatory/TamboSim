# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(openssl_FRAMEWORKS_FOUND_RELWITHDEBINFO "") # Will be filled later
conan_find_apple_frameworks(openssl_FRAMEWORKS_FOUND_RELWITHDEBINFO "${openssl_FRAMEWORKS_RELWITHDEBINFO}" "${openssl_FRAMEWORK_DIRS_RELWITHDEBINFO}")

set(openssl_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET openssl_DEPS_TARGET)
    add_library(openssl_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET openssl_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:RelWithDebInfo>:${openssl_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:${openssl_SYSTEM_LIBS_RELWITHDEBINFO}>
             $<$<CONFIG:RelWithDebInfo>:OpenSSL::Crypto;ZLIB::ZLIB>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### openssl_DEPS_TARGET to all of them
conan_package_library_targets("${openssl_LIBS_RELWITHDEBINFO}"    # libraries
                              "${openssl_LIB_DIRS_RELWITHDEBINFO}" # package_libdir
                              "${openssl_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${openssl_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${openssl_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              openssl_DEPS_TARGET
                              openssl_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELWITHDEBINFO"
                              "openssl"    # package_name
                              "${openssl_NO_SONAME_MODE_RELWITHDEBINFO}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${openssl_BUILD_DIRS_RELWITHDEBINFO} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES RelWithDebInfo ########################################

    ########## COMPONENT OpenSSL::SSL #############

        set(openssl_OpenSSL_SSL_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(openssl_OpenSSL_SSL_FRAMEWORKS_FOUND_RELWITHDEBINFO "${openssl_OpenSSL_SSL_FRAMEWORKS_RELWITHDEBINFO}" "${openssl_OpenSSL_SSL_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(openssl_OpenSSL_SSL_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET openssl_OpenSSL_SSL_DEPS_TARGET)
            add_library(openssl_OpenSSL_SSL_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET openssl_OpenSSL_SSL_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'openssl_OpenSSL_SSL_DEPS_TARGET' to all of them
        conan_package_library_targets("${openssl_OpenSSL_SSL_LIBS_RELWITHDEBINFO}"
                              "${openssl_OpenSSL_SSL_LIB_DIRS_RELWITHDEBINFO}"
                              "${openssl_OpenSSL_SSL_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${openssl_OpenSSL_SSL_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${openssl_OpenSSL_SSL_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              openssl_OpenSSL_SSL_DEPS_TARGET
                              openssl_OpenSSL_SSL_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "openssl_OpenSSL_SSL"
                              "${openssl_OpenSSL_SSL_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET OpenSSL::SSL
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_LIBRARIES_TARGETS}>
                     )

        if("${openssl_OpenSSL_SSL_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET OpenSSL::SSL
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         openssl_OpenSSL_SSL_DEPS_TARGET)
        endif()

        set_property(TARGET OpenSSL::SSL APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET OpenSSL::SSL APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET OpenSSL::SSL APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET OpenSSL::SSL APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET OpenSSL::SSL APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_SSL_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## COMPONENT OpenSSL::Crypto #############

        set(openssl_OpenSSL_Crypto_FRAMEWORKS_FOUND_RELWITHDEBINFO "")
        conan_find_apple_frameworks(openssl_OpenSSL_Crypto_FRAMEWORKS_FOUND_RELWITHDEBINFO "${openssl_OpenSSL_Crypto_FRAMEWORKS_RELWITHDEBINFO}" "${openssl_OpenSSL_Crypto_FRAMEWORK_DIRS_RELWITHDEBINFO}")

        set(openssl_OpenSSL_Crypto_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET openssl_OpenSSL_Crypto_DEPS_TARGET)
            add_library(openssl_OpenSSL_Crypto_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET openssl_OpenSSL_Crypto_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_FRAMEWORKS_FOUND_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_SYSTEM_LIBS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_DEPENDENCIES_RELWITHDEBINFO}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'openssl_OpenSSL_Crypto_DEPS_TARGET' to all of them
        conan_package_library_targets("${openssl_OpenSSL_Crypto_LIBS_RELWITHDEBINFO}"
                              "${openssl_OpenSSL_Crypto_LIB_DIRS_RELWITHDEBINFO}"
                              "${openssl_OpenSSL_Crypto_BIN_DIRS_RELWITHDEBINFO}" # package_bindir
                              "${openssl_OpenSSL_Crypto_LIBRARY_TYPE_RELWITHDEBINFO}"
                              "${openssl_OpenSSL_Crypto_IS_HOST_WINDOWS_RELWITHDEBINFO}"
                              openssl_OpenSSL_Crypto_DEPS_TARGET
                              openssl_OpenSSL_Crypto_LIBRARIES_TARGETS
                              "_RELWITHDEBINFO"
                              "openssl_OpenSSL_Crypto"
                              "${openssl_OpenSSL_Crypto_NO_SONAME_MODE_RELWITHDEBINFO}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET OpenSSL::Crypto
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_OBJECTS_RELWITHDEBINFO}>
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_LIBRARIES_TARGETS}>
                     )

        if("${openssl_OpenSSL_Crypto_LIBS_RELWITHDEBINFO}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET OpenSSL::Crypto
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         openssl_OpenSSL_Crypto_DEPS_TARGET)
        endif()

        set_property(TARGET OpenSSL::Crypto APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_LINKER_FLAGS_RELWITHDEBINFO}>)
        set_property(TARGET OpenSSL::Crypto APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_INCLUDE_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET OpenSSL::Crypto APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_LIB_DIRS_RELWITHDEBINFO}>)
        set_property(TARGET OpenSSL::Crypto APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_COMPILE_DEFINITIONS_RELWITHDEBINFO}>)
        set_property(TARGET OpenSSL::Crypto APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:RelWithDebInfo>:${openssl_OpenSSL_Crypto_COMPILE_OPTIONS_RELWITHDEBINFO}>)

    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET openssl::openssl APPEND PROPERTY INTERFACE_LINK_LIBRARIES OpenSSL::SSL)
    set_property(TARGET openssl::openssl APPEND PROPERTY INTERFACE_LINK_LIBRARIES OpenSSL::Crypto)

########## For the modules (FindXXX)
set(openssl_LIBRARIES_RELWITHDEBINFO openssl::openssl)
