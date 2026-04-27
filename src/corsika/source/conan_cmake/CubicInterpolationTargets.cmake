# Load the debug and release variables
file(GLOB DATA_FILES "${CMAKE_CURRENT_LIST_DIR}/CubicInterpolation-*-data.cmake")

foreach(f ${DATA_FILES})
    include(${f})
endforeach()

# Create the targets for all the components
foreach(_COMPONENT ${cubicinterpolation_COMPONENT_NAMES} )
    if(NOT TARGET ${_COMPONENT})
        add_library(${_COMPONENT} INTERFACE IMPORTED)
        message(${CubicInterpolation_MESSAGE_MODE} "Conan: Component target declared '${_COMPONENT}'")
    endif()
endforeach()

if(NOT TARGET CubicInterpolation::CubicInterpolation)
    add_library(CubicInterpolation::CubicInterpolation INTERFACE IMPORTED)
    message(${CubicInterpolation_MESSAGE_MODE} "Conan: Target declared 'CubicInterpolation::CubicInterpolation'")
endif()
# Load the debug and release library finders
file(GLOB CONFIG_FILES "${CMAKE_CURRENT_LIST_DIR}/CubicInterpolation-Target-*.cmake")

foreach(f ${CONFIG_FILES})
    include(${f})
endforeach()