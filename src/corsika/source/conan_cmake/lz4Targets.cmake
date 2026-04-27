# Load the debug and release variables
file(GLOB DATA_FILES "${CMAKE_CURRENT_LIST_DIR}/lz4-*-data.cmake")

foreach(f ${DATA_FILES})
    include(${f})
endforeach()

# Create the targets for all the components
foreach(_COMPONENT ${lz4_COMPONENT_NAMES} )
    if(NOT TARGET ${_COMPONENT})
        add_library(${_COMPONENT} INTERFACE IMPORTED)
        message(${lz4_MESSAGE_MODE} "Conan: Component target declared '${_COMPONENT}'")
    endif()
endforeach()

if(NOT TARGET LZ4::lz4_static)
    add_library(LZ4::lz4_static INTERFACE IMPORTED)
    message(${lz4_MESSAGE_MODE} "Conan: Target declared 'LZ4::lz4_static'")
endif()
if(NOT TARGET lz4::lz4)
    add_library(lz4::lz4 INTERFACE IMPORTED)
    set_property(TARGET lz4::lz4 PROPERTY INTERFACE_LINK_LIBRARIES LZ4::lz4_static)
endif()
# Load the debug and release library finders
file(GLOB CONFIG_FILES "${CMAKE_CURRENT_LIST_DIR}/lz4-Target-*.cmake")

foreach(f ${CONFIG_FILES})
    include(${f})
endforeach()