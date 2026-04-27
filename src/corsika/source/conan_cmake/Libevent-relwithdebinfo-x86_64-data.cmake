########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

list(APPEND libevent_COMPONENT_NAMES libevent::core libevent::extra libevent::openssl libevent::pthreads)
list(REMOVE_DUPLICATES libevent_COMPONENT_NAMES)
if(DEFINED libevent_FIND_DEPENDENCY_NAMES)
  list(APPEND libevent_FIND_DEPENDENCY_NAMES OpenSSL)
  list(REMOVE_DUPLICATES libevent_FIND_DEPENDENCY_NAMES)
else()
  set(libevent_FIND_DEPENDENCY_NAMES OpenSSL)
endif()
set(OpenSSL_FIND_MODE "NO_MODULE")

########### VARIABLES #######################################################################
#############################################################################################
set(libevent_PACKAGE_FOLDER_RELWITHDEBINFO "/n/home09/tkrishnan/.conan2/p/b/libev41e98abc5ae7f/p")
set(libevent_BUILD_MODULES_PATHS_RELWITHDEBINFO )


set(libevent_INCLUDE_DIRS_RELWITHDEBINFO )
set(libevent_RES_DIRS_RELWITHDEBINFO )
set(libevent_DEFINITIONS_RELWITHDEBINFO )
set(libevent_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_OBJECTS_RELWITHDEBINFO )
set(libevent_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(libevent_COMPILE_OPTIONS_C_RELWITHDEBINFO )
set(libevent_COMPILE_OPTIONS_CXX_RELWITHDEBINFO )
set(libevent_LIB_DIRS_RELWITHDEBINFO "${libevent_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(libevent_BIN_DIRS_RELWITHDEBINFO )
set(libevent_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(libevent_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(libevent_LIBS_RELWITHDEBINFO event_pthreads event_openssl event_extra event_core)
set(libevent_SYSTEM_LIBS_RELWITHDEBINFO pthread)
set(libevent_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(libevent_FRAMEWORKS_RELWITHDEBINFO )
set(libevent_BUILD_DIRS_RELWITHDEBINFO )
set(libevent_NO_SONAME_MODE_RELWITHDEBINFO FALSE)


# COMPOUND VARIABLES
set(libevent_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${libevent_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${libevent_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
set(libevent_LINKER_FLAGS_RELWITHDEBINFO
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${libevent_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${libevent_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${libevent_EXE_LINK_FLAGS_RELWITHDEBINFO}>")


set(libevent_COMPONENTS_RELWITHDEBINFO libevent::core libevent::extra libevent::openssl libevent::pthreads)
########### COMPONENT libevent::pthreads VARIABLES ############################################

set(libevent_libevent_pthreads_INCLUDE_DIRS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_LIB_DIRS_RELWITHDEBINFO "${libevent_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(libevent_libevent_pthreads_BIN_DIRS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(libevent_libevent_pthreads_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(libevent_libevent_pthreads_RES_DIRS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_DEFINITIONS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_OBJECTS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(libevent_libevent_pthreads_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(libevent_libevent_pthreads_LIBS_RELWITHDEBINFO event_pthreads)
set(libevent_libevent_pthreads_SYSTEM_LIBS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_FRAMEWORKS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_DEPENDENCIES_RELWITHDEBINFO libevent::core)
set(libevent_libevent_pthreads_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_libevent_pthreads_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(libevent_libevent_pthreads_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${libevent_libevent_pthreads_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${libevent_libevent_pthreads_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${libevent_libevent_pthreads_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(libevent_libevent_pthreads_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${libevent_libevent_pthreads_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${libevent_libevent_pthreads_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT libevent::openssl VARIABLES ############################################

set(libevent_libevent_openssl_INCLUDE_DIRS_RELWITHDEBINFO )
set(libevent_libevent_openssl_LIB_DIRS_RELWITHDEBINFO "${libevent_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(libevent_libevent_openssl_BIN_DIRS_RELWITHDEBINFO )
set(libevent_libevent_openssl_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(libevent_libevent_openssl_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(libevent_libevent_openssl_RES_DIRS_RELWITHDEBINFO )
set(libevent_libevent_openssl_DEFINITIONS_RELWITHDEBINFO )
set(libevent_libevent_openssl_OBJECTS_RELWITHDEBINFO )
set(libevent_libevent_openssl_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(libevent_libevent_openssl_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(libevent_libevent_openssl_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(libevent_libevent_openssl_LIBS_RELWITHDEBINFO event_openssl)
set(libevent_libevent_openssl_SYSTEM_LIBS_RELWITHDEBINFO )
set(libevent_libevent_openssl_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(libevent_libevent_openssl_FRAMEWORKS_RELWITHDEBINFO )
set(libevent_libevent_openssl_DEPENDENCIES_RELWITHDEBINFO libevent::core openssl::openssl)
set(libevent_libevent_openssl_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_libevent_openssl_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_libevent_openssl_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(libevent_libevent_openssl_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${libevent_libevent_openssl_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${libevent_libevent_openssl_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${libevent_libevent_openssl_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(libevent_libevent_openssl_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${libevent_libevent_openssl_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${libevent_libevent_openssl_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT libevent::extra VARIABLES ############################################

set(libevent_libevent_extra_INCLUDE_DIRS_RELWITHDEBINFO )
set(libevent_libevent_extra_LIB_DIRS_RELWITHDEBINFO "${libevent_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(libevent_libevent_extra_BIN_DIRS_RELWITHDEBINFO )
set(libevent_libevent_extra_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(libevent_libevent_extra_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(libevent_libevent_extra_RES_DIRS_RELWITHDEBINFO )
set(libevent_libevent_extra_DEFINITIONS_RELWITHDEBINFO )
set(libevent_libevent_extra_OBJECTS_RELWITHDEBINFO )
set(libevent_libevent_extra_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(libevent_libevent_extra_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(libevent_libevent_extra_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(libevent_libevent_extra_LIBS_RELWITHDEBINFO event_extra)
set(libevent_libevent_extra_SYSTEM_LIBS_RELWITHDEBINFO )
set(libevent_libevent_extra_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(libevent_libevent_extra_FRAMEWORKS_RELWITHDEBINFO )
set(libevent_libevent_extra_DEPENDENCIES_RELWITHDEBINFO libevent::core)
set(libevent_libevent_extra_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_libevent_extra_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_libevent_extra_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(libevent_libevent_extra_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${libevent_libevent_extra_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${libevent_libevent_extra_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${libevent_libevent_extra_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(libevent_libevent_extra_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${libevent_libevent_extra_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${libevent_libevent_extra_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT libevent::core VARIABLES ############################################

set(libevent_libevent_core_INCLUDE_DIRS_RELWITHDEBINFO )
set(libevent_libevent_core_LIB_DIRS_RELWITHDEBINFO "${libevent_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(libevent_libevent_core_BIN_DIRS_RELWITHDEBINFO )
set(libevent_libevent_core_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(libevent_libevent_core_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(libevent_libevent_core_RES_DIRS_RELWITHDEBINFO )
set(libevent_libevent_core_DEFINITIONS_RELWITHDEBINFO )
set(libevent_libevent_core_OBJECTS_RELWITHDEBINFO )
set(libevent_libevent_core_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(libevent_libevent_core_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(libevent_libevent_core_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(libevent_libevent_core_LIBS_RELWITHDEBINFO event_core)
set(libevent_libevent_core_SYSTEM_LIBS_RELWITHDEBINFO pthread)
set(libevent_libevent_core_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(libevent_libevent_core_FRAMEWORKS_RELWITHDEBINFO )
set(libevent_libevent_core_DEPENDENCIES_RELWITHDEBINFO )
set(libevent_libevent_core_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_libevent_core_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(libevent_libevent_core_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(libevent_libevent_core_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${libevent_libevent_core_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${libevent_libevent_core_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${libevent_libevent_core_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(libevent_libevent_core_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${libevent_libevent_core_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${libevent_libevent_core_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")