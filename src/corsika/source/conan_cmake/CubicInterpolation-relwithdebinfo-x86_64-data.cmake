########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

set(cubicinterpolation_COMPONENT_NAMES "")
if(DEFINED cubicinterpolation_FIND_DEPENDENCY_NAMES)
  list(APPEND cubicinterpolation_FIND_DEPENDENCY_NAMES Boost Eigen3)
  list(REMOVE_DUPLICATES cubicinterpolation_FIND_DEPENDENCY_NAMES)
else()
  set(cubicinterpolation_FIND_DEPENDENCY_NAMES Boost Eigen3)
endif()
set(Boost_FIND_MODE "NO_MODULE")
set(Eigen3_FIND_MODE "NO_MODULE")

########### VARIABLES #######################################################################
#############################################################################################
set(cubicinterpolation_PACKAGE_FOLDER_RELWITHDEBINFO "/n/home09/tkrishnan/.conan2/p/b/cubic230072d115bcf/p")
set(cubicinterpolation_BUILD_MODULES_PATHS_RELWITHDEBINFO )


set(cubicinterpolation_INCLUDE_DIRS_RELWITHDEBINFO "${cubicinterpolation_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(cubicinterpolation_RES_DIRS_RELWITHDEBINFO )
set(cubicinterpolation_DEFINITIONS_RELWITHDEBINFO )
set(cubicinterpolation_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(cubicinterpolation_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(cubicinterpolation_OBJECTS_RELWITHDEBINFO )
set(cubicinterpolation_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(cubicinterpolation_COMPILE_OPTIONS_C_RELWITHDEBINFO )
set(cubicinterpolation_COMPILE_OPTIONS_CXX_RELWITHDEBINFO )
set(cubicinterpolation_LIB_DIRS_RELWITHDEBINFO "${cubicinterpolation_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(cubicinterpolation_BIN_DIRS_RELWITHDEBINFO )
set(cubicinterpolation_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(cubicinterpolation_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(cubicinterpolation_LIBS_RELWITHDEBINFO CubicInterpolation)
set(cubicinterpolation_SYSTEM_LIBS_RELWITHDEBINFO )
set(cubicinterpolation_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(cubicinterpolation_FRAMEWORKS_RELWITHDEBINFO )
set(cubicinterpolation_BUILD_DIRS_RELWITHDEBINFO )
set(cubicinterpolation_NO_SONAME_MODE_RELWITHDEBINFO FALSE)


# COMPOUND VARIABLES
set(cubicinterpolation_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${cubicinterpolation_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${cubicinterpolation_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
set(cubicinterpolation_LINKER_FLAGS_RELWITHDEBINFO
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${cubicinterpolation_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${cubicinterpolation_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${cubicinterpolation_EXE_LINK_FLAGS_RELWITHDEBINFO}>")


set(cubicinterpolation_COMPONENTS_RELWITHDEBINFO )