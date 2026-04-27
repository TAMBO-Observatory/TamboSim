########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

list(APPEND boost_COMPONENT_NAMES Boost::diagnostic_definitions Boost::disable_autolinking Boost::dynamic_linking Boost::headers Boost::boost boost::_libboost Boost::atomic Boost::charconv Boost::exception Boost::math Boost::math_c99 Boost::math_c99f Boost::math_c99l Boost::math_tr1 Boost::math_tr1f Boost::math_tr1l Boost::regex Boost::serialization Boost::system Boost::url Boost::wserialization Boost::chrono Boost::filesystem Boost::random Boost::iostreams)
list(REMOVE_DUPLICATES boost_COMPONENT_NAMES)
if(DEFINED boost_FIND_DEPENDENCY_NAMES)
  list(APPEND boost_FIND_DEPENDENCY_NAMES ZLIB BZip2)
  list(REMOVE_DUPLICATES boost_FIND_DEPENDENCY_NAMES)
else()
  set(boost_FIND_DEPENDENCY_NAMES ZLIB BZip2)
endif()
set(ZLIB_FIND_MODE "NO_MODULE")
set(BZip2_FIND_MODE "NO_MODULE")

########### VARIABLES #######################################################################
#############################################################################################
set(boost_PACKAGE_FOLDER_RELWITHDEBINFO "/n/home09/tkrishnan/.conan2/p/b/boost439754c02dfe1/p")
set(boost_BUILD_MODULES_PATHS_RELWITHDEBINFO )


set(boost_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_RES_DIRS_RELWITHDEBINFO )
set(boost_DEFINITIONS_RELWITHDEBINFO )
set(boost_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_OBJECTS_RELWITHDEBINFO )
set(boost_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_COMPILE_OPTIONS_C_RELWITHDEBINFO )
set(boost_COMPILE_OPTIONS_CXX_RELWITHDEBINFO )
set(boost_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_BIN_DIRS_RELWITHDEBINFO )
set(boost_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_LIBS_RELWITHDEBINFO boost_iostreams boost_random boost_filesystem boost_chrono boost_wserialization boost_url boost_serialization boost_regex boost_math_tr1l boost_math_tr1f boost_math_tr1 boost_math_c99l boost_math_c99f boost_math_c99 boost_exception boost_charconv boost_atomic)
set(boost_SYSTEM_LIBS_RELWITHDEBINFO rt pthread)
set(boost_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_FRAMEWORKS_RELWITHDEBINFO )
set(boost_BUILD_DIRS_RELWITHDEBINFO )
set(boost_NO_SONAME_MODE_RELWITHDEBINFO FALSE)


# COMPOUND VARIABLES
set(boost_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
set(boost_LINKER_FLAGS_RELWITHDEBINFO
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_EXE_LINK_FLAGS_RELWITHDEBINFO}>")


set(boost_COMPONENTS_RELWITHDEBINFO Boost::diagnostic_definitions Boost::disable_autolinking Boost::dynamic_linking Boost::headers Boost::boost boost::_libboost Boost::atomic Boost::charconv Boost::exception Boost::math Boost::math_c99 Boost::math_c99f Boost::math_c99l Boost::math_tr1 Boost::math_tr1f Boost::math_tr1l Boost::regex Boost::serialization Boost::system Boost::url Boost::wserialization Boost::chrono Boost::filesystem Boost::random Boost::iostreams)
########### COMPONENT Boost::iostreams VARIABLES ############################################

set(boost_Boost_iostreams_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_iostreams_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_iostreams_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_iostreams_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_iostreams_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_iostreams_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_iostreams_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_iostreams_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_iostreams_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_iostreams_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_iostreams_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_iostreams_LIBS_RELWITHDEBINFO boost_iostreams)
set(boost_Boost_iostreams_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_iostreams_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_iostreams_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_iostreams_DEPENDENCIES_RELWITHDEBINFO Boost::random Boost::regex boost::_libboost BZip2::BZip2 ZLIB::ZLIB)
set(boost_Boost_iostreams_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_iostreams_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_iostreams_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_iostreams_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_iostreams_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_iostreams_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_iostreams_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_iostreams_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_iostreams_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_iostreams_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::random VARIABLES ############################################

set(boost_Boost_random_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_random_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_random_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_random_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_random_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_random_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_random_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_random_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_random_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_random_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_random_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_random_LIBS_RELWITHDEBINFO boost_random)
set(boost_Boost_random_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_random_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_random_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_random_DEPENDENCIES_RELWITHDEBINFO Boost::system boost::_libboost)
set(boost_Boost_random_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_random_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_random_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_random_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_random_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_random_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_random_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_random_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_random_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_random_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::filesystem VARIABLES ############################################

set(boost_Boost_filesystem_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_filesystem_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_filesystem_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_filesystem_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_filesystem_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_filesystem_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_filesystem_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_filesystem_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_filesystem_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_filesystem_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_filesystem_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_filesystem_LIBS_RELWITHDEBINFO boost_filesystem)
set(boost_Boost_filesystem_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_filesystem_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_filesystem_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_filesystem_DEPENDENCIES_RELWITHDEBINFO Boost::atomic Boost::system boost::_libboost)
set(boost_Boost_filesystem_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_filesystem_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_filesystem_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_filesystem_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_filesystem_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_filesystem_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_filesystem_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_filesystem_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_filesystem_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_filesystem_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::chrono VARIABLES ############################################

set(boost_Boost_chrono_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_chrono_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_chrono_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_chrono_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_chrono_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_chrono_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_chrono_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_chrono_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_chrono_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_chrono_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_chrono_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_chrono_LIBS_RELWITHDEBINFO boost_chrono)
set(boost_Boost_chrono_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_chrono_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_chrono_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_chrono_DEPENDENCIES_RELWITHDEBINFO Boost::system boost::_libboost)
set(boost_Boost_chrono_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_chrono_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_chrono_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_chrono_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_chrono_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_chrono_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_chrono_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_chrono_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_chrono_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_chrono_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::wserialization VARIABLES ############################################

set(boost_Boost_wserialization_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_wserialization_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_wserialization_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_wserialization_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_wserialization_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_wserialization_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_wserialization_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_wserialization_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_wserialization_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_wserialization_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_wserialization_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_wserialization_LIBS_RELWITHDEBINFO boost_wserialization)
set(boost_Boost_wserialization_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_wserialization_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_wserialization_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_wserialization_DEPENDENCIES_RELWITHDEBINFO Boost::serialization boost::_libboost)
set(boost_Boost_wserialization_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_wserialization_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_wserialization_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_wserialization_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_wserialization_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_wserialization_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_wserialization_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_wserialization_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_wserialization_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_wserialization_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::url VARIABLES ############################################

set(boost_Boost_url_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_url_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_url_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_url_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_url_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_url_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_url_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_url_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_url_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_url_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_url_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_url_LIBS_RELWITHDEBINFO boost_url)
set(boost_Boost_url_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_url_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_url_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_url_DEPENDENCIES_RELWITHDEBINFO Boost::system boost::_libboost)
set(boost_Boost_url_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_url_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_url_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_url_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_url_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_url_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_url_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_url_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_url_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_url_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::system VARIABLES ############################################

set(boost_Boost_system_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_system_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_system_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_system_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_system_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_system_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_system_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_system_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_system_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_system_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_system_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_system_LIBS_RELWITHDEBINFO )
set(boost_Boost_system_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_system_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_system_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_system_DEPENDENCIES_RELWITHDEBINFO boost::_libboost)
set(boost_Boost_system_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_system_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_system_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_system_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_system_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_system_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_system_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_system_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_system_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_system_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::serialization VARIABLES ############################################

set(boost_Boost_serialization_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_serialization_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_serialization_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_serialization_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_serialization_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_serialization_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_serialization_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_serialization_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_serialization_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_serialization_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_serialization_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_serialization_LIBS_RELWITHDEBINFO boost_serialization)
set(boost_Boost_serialization_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_serialization_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_serialization_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_serialization_DEPENDENCIES_RELWITHDEBINFO boost::_libboost)
set(boost_Boost_serialization_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_serialization_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_serialization_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_serialization_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_serialization_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_serialization_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_serialization_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_serialization_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_serialization_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_serialization_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::regex VARIABLES ############################################

set(boost_Boost_regex_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_regex_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_regex_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_regex_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_regex_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_regex_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_regex_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_regex_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_regex_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_regex_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_regex_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_regex_LIBS_RELWITHDEBINFO boost_regex)
set(boost_Boost_regex_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_regex_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_regex_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_regex_DEPENDENCIES_RELWITHDEBINFO boost::_libboost)
set(boost_Boost_regex_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_regex_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_regex_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_regex_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_regex_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_regex_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_regex_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_regex_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_regex_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_regex_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::math_tr1l VARIABLES ############################################

set(boost_Boost_math_tr1l_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_math_tr1l_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_math_tr1l_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_math_tr1l_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_math_tr1l_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_math_tr1l_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_math_tr1l_LIBS_RELWITHDEBINFO boost_math_tr1l)
set(boost_Boost_math_tr1l_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_DEPENDENCIES_RELWITHDEBINFO Boost::math boost::_libboost)
set(boost_Boost_math_tr1l_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_tr1l_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_math_tr1l_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_math_tr1l_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_math_tr1l_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_math_tr1l_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_math_tr1l_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_math_tr1l_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_math_tr1l_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::math_tr1f VARIABLES ############################################

set(boost_Boost_math_tr1f_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_math_tr1f_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_math_tr1f_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_math_tr1f_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_math_tr1f_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_math_tr1f_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_math_tr1f_LIBS_RELWITHDEBINFO boost_math_tr1f)
set(boost_Boost_math_tr1f_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_DEPENDENCIES_RELWITHDEBINFO Boost::math boost::_libboost)
set(boost_Boost_math_tr1f_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_tr1f_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_math_tr1f_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_math_tr1f_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_math_tr1f_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_math_tr1f_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_math_tr1f_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_math_tr1f_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_math_tr1f_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::math_tr1 VARIABLES ############################################

set(boost_Boost_math_tr1_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_math_tr1_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_math_tr1_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_math_tr1_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_math_tr1_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_math_tr1_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_math_tr1_LIBS_RELWITHDEBINFO boost_math_tr1)
set(boost_Boost_math_tr1_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_DEPENDENCIES_RELWITHDEBINFO Boost::math boost::_libboost)
set(boost_Boost_math_tr1_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_tr1_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_math_tr1_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_math_tr1_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_math_tr1_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_math_tr1_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_math_tr1_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_math_tr1_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_math_tr1_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::math_c99l VARIABLES ############################################

set(boost_Boost_math_c99l_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_math_c99l_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_math_c99l_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_math_c99l_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_math_c99l_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_math_c99l_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_math_c99l_LIBS_RELWITHDEBINFO boost_math_c99l)
set(boost_Boost_math_c99l_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_DEPENDENCIES_RELWITHDEBINFO Boost::math boost::_libboost)
set(boost_Boost_math_c99l_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_c99l_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_math_c99l_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_math_c99l_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_math_c99l_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_math_c99l_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_math_c99l_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_math_c99l_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_math_c99l_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::math_c99f VARIABLES ############################################

set(boost_Boost_math_c99f_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_math_c99f_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_math_c99f_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_math_c99f_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_math_c99f_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_math_c99f_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_math_c99f_LIBS_RELWITHDEBINFO boost_math_c99f)
set(boost_Boost_math_c99f_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_DEPENDENCIES_RELWITHDEBINFO Boost::math boost::_libboost)
set(boost_Boost_math_c99f_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_c99f_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_math_c99f_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_math_c99f_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_math_c99f_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_math_c99f_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_math_c99f_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_math_c99f_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_math_c99f_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::math_c99 VARIABLES ############################################

set(boost_Boost_math_c99_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_math_c99_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_math_c99_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_math_c99_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_math_c99_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_c99_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_math_c99_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_c99_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_math_c99_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_math_c99_LIBS_RELWITHDEBINFO boost_math_c99)
set(boost_Boost_math_c99_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_math_c99_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_c99_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_math_c99_DEPENDENCIES_RELWITHDEBINFO Boost::math boost::_libboost)
set(boost_Boost_math_c99_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_c99_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_c99_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_math_c99_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_math_c99_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_math_c99_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_math_c99_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_math_c99_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_math_c99_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_math_c99_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::math VARIABLES ############################################

set(boost_Boost_math_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_math_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_math_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_math_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_math_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_math_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_math_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_math_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_math_LIBS_RELWITHDEBINFO )
set(boost_Boost_math_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_math_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_math_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_math_DEPENDENCIES_RELWITHDEBINFO boost::_libboost)
set(boost_Boost_math_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_math_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_math_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_math_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_math_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_math_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_math_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_math_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_math_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::exception VARIABLES ############################################

set(boost_Boost_exception_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_exception_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_exception_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_exception_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_exception_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_exception_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_exception_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_exception_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_exception_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_exception_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_exception_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_exception_LIBS_RELWITHDEBINFO boost_exception)
set(boost_Boost_exception_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_exception_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_exception_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_exception_DEPENDENCIES_RELWITHDEBINFO boost::_libboost)
set(boost_Boost_exception_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_exception_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_exception_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_exception_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_exception_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_exception_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_exception_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_exception_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_exception_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_exception_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::charconv VARIABLES ############################################

set(boost_Boost_charconv_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_charconv_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_charconv_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_charconv_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_charconv_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_charconv_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_charconv_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_charconv_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_charconv_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_charconv_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_charconv_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_charconv_LIBS_RELWITHDEBINFO boost_charconv)
set(boost_Boost_charconv_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_charconv_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_charconv_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_charconv_DEPENDENCIES_RELWITHDEBINFO boost::_libboost)
set(boost_Boost_charconv_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_charconv_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_charconv_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_charconv_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_charconv_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_charconv_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_charconv_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_charconv_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_charconv_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_charconv_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::atomic VARIABLES ############################################

set(boost_Boost_atomic_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_atomic_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_atomic_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_atomic_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_atomic_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_atomic_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_atomic_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_atomic_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_atomic_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_atomic_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_atomic_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_atomic_LIBS_RELWITHDEBINFO boost_atomic)
set(boost_Boost_atomic_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_atomic_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_atomic_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_atomic_DEPENDENCIES_RELWITHDEBINFO boost::_libboost)
set(boost_Boost_atomic_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_atomic_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_atomic_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_atomic_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_atomic_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_atomic_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_atomic_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_atomic_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_atomic_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_atomic_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT boost::_libboost VARIABLES ############################################

set(boost_boost__libboost_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_boost__libboost_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_boost__libboost_BIN_DIRS_RELWITHDEBINFO )
set(boost_boost__libboost_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_boost__libboost_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_boost__libboost_RES_DIRS_RELWITHDEBINFO )
set(boost_boost__libboost_DEFINITIONS_RELWITHDEBINFO )
set(boost_boost__libboost_OBJECTS_RELWITHDEBINFO )
set(boost_boost__libboost_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_boost__libboost_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_boost__libboost_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_boost__libboost_LIBS_RELWITHDEBINFO )
set(boost_boost__libboost_SYSTEM_LIBS_RELWITHDEBINFO rt pthread)
set(boost_boost__libboost_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_boost__libboost_FRAMEWORKS_RELWITHDEBINFO )
set(boost_boost__libboost_DEPENDENCIES_RELWITHDEBINFO Boost::headers)
set(boost_boost__libboost_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_boost__libboost_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_boost__libboost_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_boost__libboost_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_boost__libboost_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_boost__libboost_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_boost__libboost_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_boost__libboost_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_boost__libboost_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_boost__libboost_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::boost VARIABLES ############################################

set(boost_Boost_boost_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_boost_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_boost_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_boost_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_boost_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_boost_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_boost_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_boost_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_boost_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_boost_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_boost_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_boost_LIBS_RELWITHDEBINFO )
set(boost_Boost_boost_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_boost_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_boost_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_boost_DEPENDENCIES_RELWITHDEBINFO Boost::headers)
set(boost_Boost_boost_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_boost_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_boost_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_boost_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_boost_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_boost_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_boost_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_boost_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_boost_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_boost_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::headers VARIABLES ############################################

set(boost_Boost_headers_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_headers_LIB_DIRS_RELWITHDEBINFO )
set(boost_Boost_headers_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_headers_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_headers_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_headers_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_headers_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_headers_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_headers_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_headers_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_headers_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_headers_LIBS_RELWITHDEBINFO )
set(boost_Boost_headers_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_headers_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_headers_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_headers_DEPENDENCIES_RELWITHDEBINFO Boost::diagnostic_definitions Boost::disable_autolinking Boost::dynamic_linking)
set(boost_Boost_headers_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_headers_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_headers_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_headers_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_headers_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_headers_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_headers_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_headers_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_headers_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_headers_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::dynamic_linking VARIABLES ############################################

set(boost_Boost_dynamic_linking_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_dynamic_linking_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_dynamic_linking_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_dynamic_linking_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_dynamic_linking_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_dynamic_linking_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_dynamic_linking_LIBS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_DEPENDENCIES_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_dynamic_linking_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_dynamic_linking_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_dynamic_linking_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_dynamic_linking_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_dynamic_linking_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_dynamic_linking_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_dynamic_linking_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_dynamic_linking_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::disable_autolinking VARIABLES ############################################

set(boost_Boost_disable_autolinking_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_disable_autolinking_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_disable_autolinking_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_disable_autolinking_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_disable_autolinking_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_disable_autolinking_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_disable_autolinking_LIBS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_DEPENDENCIES_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_disable_autolinking_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_disable_autolinking_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_disable_autolinking_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_disable_autolinking_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_disable_autolinking_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_disable_autolinking_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_disable_autolinking_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_disable_autolinking_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Boost::diagnostic_definitions VARIABLES ############################################

set(boost_Boost_diagnostic_definitions_INCLUDE_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(boost_Boost_diagnostic_definitions_LIB_DIRS_RELWITHDEBINFO "${boost_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(boost_Boost_diagnostic_definitions_BIN_DIRS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(boost_Boost_diagnostic_definitions_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(boost_Boost_diagnostic_definitions_RES_DIRS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_OBJECTS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(boost_Boost_diagnostic_definitions_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(boost_Boost_diagnostic_definitions_LIBS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_SYSTEM_LIBS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_FRAMEWORKS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_DEPENDENCIES_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(boost_Boost_diagnostic_definitions_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(boost_Boost_diagnostic_definitions_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${boost_Boost_diagnostic_definitions_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${boost_Boost_diagnostic_definitions_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${boost_Boost_diagnostic_definitions_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(boost_Boost_diagnostic_definitions_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${boost_Boost_diagnostic_definitions_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${boost_Boost_diagnostic_definitions_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")