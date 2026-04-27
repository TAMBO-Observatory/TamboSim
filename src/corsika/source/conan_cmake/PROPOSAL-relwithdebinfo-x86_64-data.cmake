########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

set(proposal_COMPONENT_NAMES "")
if(DEFINED proposal_FIND_DEPENDENCY_NAMES)
  list(APPEND proposal_FIND_DEPENDENCY_NAMES CubicInterpolation spdlog nlohmann_json)
  list(REMOVE_DUPLICATES proposal_FIND_DEPENDENCY_NAMES)
else()
  set(proposal_FIND_DEPENDENCY_NAMES CubicInterpolation spdlog nlohmann_json)
endif()
set(CubicInterpolation_FIND_MODE "NO_MODULE")
set(spdlog_FIND_MODE "NO_MODULE")
set(nlohmann_json_FIND_MODE "NO_MODULE")

########### VARIABLES #######################################################################
#############################################################################################
set(proposal_PACKAGE_FOLDER_RELWITHDEBINFO "/n/home09/tkrishnan/.conan2/p/b/propob98fb6787c909/p")
set(proposal_BUILD_MODULES_PATHS_RELWITHDEBINFO )


set(proposal_INCLUDE_DIRS_RELWITHDEBINFO "${proposal_PACKAGE_FOLDER_RELWITHDEBINFO}/include")
set(proposal_RES_DIRS_RELWITHDEBINFO )
set(proposal_DEFINITIONS_RELWITHDEBINFO )
set(proposal_SHARED_LINK_FLAGS_RELWITHDEBINFO )
set(proposal_EXE_LINK_FLAGS_RELWITHDEBINFO )
set(proposal_OBJECTS_RELWITHDEBINFO )
set(proposal_COMPILE_DEFINITIONS_RELWITHDEBINFO )
set(proposal_COMPILE_OPTIONS_C_RELWITHDEBINFO )
set(proposal_COMPILE_OPTIONS_CXX_RELWITHDEBINFO )
set(proposal_LIB_DIRS_RELWITHDEBINFO "${proposal_PACKAGE_FOLDER_RELWITHDEBINFO}/lib")
set(proposal_BIN_DIRS_RELWITHDEBINFO )
set(proposal_LIBRARY_TYPE_RELWITHDEBINFO STATIC)
set(proposal_IS_HOST_WINDOWS_RELWITHDEBINFO 0)
set(proposal_LIBS_RELWITHDEBINFO PROPOSAL)
set(proposal_SYSTEM_LIBS_RELWITHDEBINFO )
set(proposal_FRAMEWORK_DIRS_RELWITHDEBINFO )
set(proposal_FRAMEWORKS_RELWITHDEBINFO )
set(proposal_BUILD_DIRS_RELWITHDEBINFO )
set(proposal_NO_SONAME_MODE_RELWITHDEBINFO FALSE)


# COMPOUND VARIABLES
set(proposal_COMPILE_OPTIONS_RELWITHDEBINFO
    "$<$<COMPILE_LANGUAGE:CXX>:${proposal_COMPILE_OPTIONS_CXX_RELWITHDEBINFO}>"
    "$<$<COMPILE_LANGUAGE:C>:${proposal_COMPILE_OPTIONS_C_RELWITHDEBINFO}>")
set(proposal_LINKER_FLAGS_RELWITHDEBINFO
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${proposal_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${proposal_SHARED_LINK_FLAGS_RELWITHDEBINFO}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${proposal_EXE_LINK_FLAGS_RELWITHDEBINFO}>")


set(proposal_COMPONENTS_RELWITHDEBINFO )