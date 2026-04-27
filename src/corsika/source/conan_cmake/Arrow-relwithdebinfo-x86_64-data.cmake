########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

list(APPEND arrow_COMPONENT_NAMES Arrow::arrow_static Parquet::parquet_static)
list(REMOVE_DUPLICATES arrow_COMPONENT_NAMES)
if(DEFINED arrow_FIND_DEPENDENCY_NAMES)
  list(APPEND arrow_FIND_DEPENDENCY_NAMES Thrift lz4 re2 Boost ZLIB)
  list(REMOVE_DUPLICATES arrow_FIND_DEPENDENCY_NAMES)
else()
  set(arrow_FIND_DEPENDENCY_NAMES Thrift lz4 re2 Boost ZLIB)
endif()
set(Thrift_FIND_MODE "NO_MODULE")
set(lz4_FIND_MODE "NO_MODULE")
set(re2_FIND_MODE "NO_MODULE")
set(Boost_FIND_MODE "NO_MODULE")
set(ZLIB_FIND_MODE "NO_MODULE")

########### VARIABLES #######################################################################
#############################################################################################
set(arrow_PACKAGE_FOLDER_RELWITHDEBINFO "/n/home09/tkrishnan/.conan2/p/b/arrowfcac7a8783ef9/p")
set(arrow_BUILD_MODULES_PATHS_RELWITHDEBINFO )


set(arrow_INCLUDE_DIRS_RELWITHDEBINFO "${arrow_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(arrow_RES_DIRS_RELWITHDEBINFO )
set(arrow_DEFINITIONS_RELWITHDEBINFO "-DPARQUET_STATIC"
			"-DARROW_STATIC")
set(arrow_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(arrow_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(arrow_OBJECTS_RELWITHDEBINFO )
set(arrow_COMPILE_DEFINITIONS_RELWITHDEBINFO "PARQUET_STATIC"
			"ARROW_STATIC")
set(arrow_COMPILE_OPTIONS_C_RELWITHDEBINFO )
set(arrow_COMPILE_OPTIONS_CXX_RELWITHDEBINFO )
set(arrow_LIB_DIRS_RELWITHDEBINFO "${arrow_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(arrow_BIN_DIRS_RELWITHDEBINFO )
set(arrow_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(arrow_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(arrow_LIBS_RELWITHDEBINFO parquet arrow)
set(arrow_SYSTEM_LIBS_RELWITHDEBINFO pthread m dl rt)
set(arrow_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(arrow_FRAMEWORKS_RELWITHDEBINFO )
set(arrow_BUILD_DIRS_RELWITHDEBINFO )
set(arrow_NO_SONAME_MODE_RELWITHDEBINFO FALSE)


# COMPOUND VARIABLES
set(arrow_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${arrow_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${arrow_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
set(arrow_LINKER_FLAGS_RELWITHDEBINFO
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${arrow_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${arrow_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${arrow_EXE_LINK_FLAGS_RELWITHDEBINFO}>")


set(arrow_COMPONENTS_RELWITHDEBINFO Arrow::arrow_static Parquet::parquet_static)
########### COMPONENT Parquet::parquet_static VARIABLES ############################################

set(arrow_Parquet_parquet_static_INCLUDE_DIRS_RELWITHDEBINFO "${arrow_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(arrow_Parquet_parquet_static_LIB_DIRS_RELWITHDEBINFO "${arrow_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(arrow_Parquet_parquet_static_BIN_DIRS_RELWITHDEBINFO )
set(arrow_Parquet_parquet_static_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(arrow_Parquet_parquet_static_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(arrow_Parquet_parquet_static_RES_DIRS_RELWITHDEBINFO )
set(arrow_Parquet_parquet_static_DEFINITIONS_RELWITHDEBINFO "-DPARQUET_STATIC")
set(arrow_Parquet_parquet_static_OBJECTS_RELWITHDEBINFO )
set(arrow_Parquet_parquet_static_COMPILE_DEFINITIONS_RELWITHDEBINFO "PARQUET_STATIC")
set(arrow_Parquet_parquet_static_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(arrow_Parquet_parquet_static_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(arrow_Parquet_parquet_static_LIBS_RELWITHDEBINFO parquet)
set(arrow_Parquet_parquet_static_SYSTEM_LIBS_RELWITHDEBINFO )
set(arrow_Parquet_parquet_static_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(arrow_Parquet_parquet_static_FRAMEWORKS_RELWITHDEBINFO )
set(arrow_Parquet_parquet_static_DEPENDENCIES_RELWITHDEBINFO Arrow::arrow_static re2::re2)
set(arrow_Parquet_parquet_static_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(arrow_Parquet_parquet_static_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(arrow_Parquet_parquet_static_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(arrow_Parquet_parquet_static_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${arrow_Parquet_parquet_static_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${arrow_Parquet_parquet_static_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${arrow_Parquet_parquet_static_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(arrow_Parquet_parquet_static_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${arrow_Parquet_parquet_static_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${arrow_Parquet_parquet_static_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
########### COMPONENT Arrow::arrow_static VARIABLES ############################################

set(arrow_Arrow_arrow_static_INCLUDE_DIRS_RELWITHDEBINFO "${arrow_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(arrow_Arrow_arrow_static_LIB_DIRS_RELWITHDEBINFO "${arrow_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(arrow_Arrow_arrow_static_BIN_DIRS_RELWITHDEBINFO )
set(arrow_Arrow_arrow_static_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(arrow_Arrow_arrow_static_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(arrow_Arrow_arrow_static_RES_DIRS_RELWITHDEBINFO )
set(arrow_Arrow_arrow_static_DEFINITIONS_RELWITHDEBINFO "-DARROW_STATIC")
set(arrow_Arrow_arrow_static_OBJECTS_RELWITHDEBINFO )
set(arrow_Arrow_arrow_static_COMPILE_DEFINITIONS_RELWITHDEBINFO "ARROW_STATIC")
set(arrow_Arrow_arrow_static_COMPILE_OPTIONS_C_RELWITHDEBINFO "")
set(arrow_Arrow_arrow_static_COMPILE_OPTIONS_CXX_RELWITHDEBINFO "")
set(arrow_Arrow_arrow_static_LIBS_RELWITHDEBINFO arrow)
set(arrow_Arrow_arrow_static_SYSTEM_LIBS_RELWITHDEBINFO pthread m dl rt)
set(arrow_Arrow_arrow_static_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(arrow_Arrow_arrow_static_FRAMEWORKS_RELWITHDEBINFO )
set(arrow_Arrow_arrow_static_DEPENDENCIES_RELWITHDEBINFO boost::boost re2::re2 thrift::thrift-conan-do-not-use LZ4::lz4_static ZLIB::ZLIB)
set(arrow_Arrow_arrow_static_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(arrow_Arrow_arrow_static_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(arrow_Arrow_arrow_static_NO_SONAME_MODE_RELWITHDEBINFO FALSE)

# COMPOUND VARIABLES
set(arrow_Arrow_arrow_static_LINKER_FLAGS_RELWITHDEBINFO
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${arrow_Arrow_arrow_static_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${arrow_Arrow_arrow_static_SHARED_LINK_FLAGS_RELWITHDEBINFO}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${arrow_Arrow_arrow_static_EXE_LINK_FLAGS_RELWITHDEBINFO}>
)
set(arrow_Arrow_arrow_static_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${arrow_Arrow_arrow_static_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${arrow_Arrow_arrow_static_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")