# Load the debug and release variables
file(GLOB DATA_FILES "${CMAKE_CURRENT_LIST_DIR}/CLI11-*-data.cmake")

foreach(f ${DATA_FILES})
    include(${f})
endforeach()

# Create the targets for all the components
foreach(_COMPONENT ${cli11_COMPONENT_NAMES} )
    if(NOT TARGET ${_COMPONENT})
        add_library(${_COMPONENT} INTERFACE IMPORTED)
        message(${CLI11_MESSAGE_MODE} "Conan: Component target declared '${_COMPONENT}'")
    endif()
endforeach()

if(NOT TARGET CLI11::CLI11)
    add_library(CLI11::CLI11 INTERFACE IMPORTED)
    message(${CLI11_MESSAGE_MODE} "Conan: Target declared 'CLI11::CLI11'")
endif()
# Load the debug and release library finders
file(GLOB CONFIG_FILES "${CMAKE_CURRENT_LIST_DIR}/CLI11-Target-*.cmake")

foreach(f ${CONFIG_FILES})
    include(${f})
endforeach()