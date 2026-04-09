cmake_minimum_required(VERSION 3.15)
project(dawa-tts VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Platform-specific settings
if(APPLE)
    set(MODULE_SUFFIX ".dylib")
    set(MODULE_LINKER_FLAGS "-undefined;dynamic_lookup")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -fexceptions")
else()
    set(MODULE_SUFFIX ".so")
    set(MODULE_LINKER_FLAGS "-shared")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -fexceptions")
endif()

message(STATUS "Building for platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "Module suffix: ${MODULE_SUFFIX}")

# Find required packages
find_package(PkgConfig REQUIRED)

# ONNX Runtime - Try multiple methods (adapted from supertonic)
# Method 1: Try to find via CMake config
find_package(onnxruntime QUIET CONFIG)

if(NOT onnxruntime_FOUND)
    # Method 2: Try pkg-config
    pkg_check_modules(ONNXRUNTIME QUIET libonnxruntime)

    if(ONNXRUNTIME_FOUND)
        set(ONNXRUNTIME_INCLUDE_DIR ${ONNXRUNTIME_INCLUDE_DIRS})
        set(ONNXRUNTIME_LIB ${ONNXRUNTIME_LIBRARIES})
    else()
        # Method 3: Manual search in common locations
        find_path(ONNXRUNTIME_INCLUDE_DIR
            NAMES onnxruntime_cxx_api.h
            PATHS
                /usr/local/include
                /opt/homebrew/include
                /usr/include
                ${CMAKE_PREFIX_PATH}/include
            PATH_SUFFIXES onnxruntime
        )

        find_library(ONNXRUNTIME_LIB
            NAMES onnxruntime libonnxruntime
            PATHS
                /usr/local/lib
                /opt/homebrew/lib
                /usr/lib
                ${CMAKE_PREFIX_PATH}/lib
        )
    endif()

    if(NOT ONNXRUNTIME_INCLUDE_DIR OR NOT ONNXRUNTIME_LIB)
        message(FATAL_ERROR "ONNX Runtime not found. Please install it:\n"
                            "  macOS: brew install onnxruntime\n"
                            "  Linux: See README.md for installation instructions")
    endif()

    message(STATUS "Found ONNX Runtime:")
    message(STATUS "  Include: ${ONNXRUNTIME_INCLUDE_DIR}")
    message(STATUS "  Library: ${ONNXRUNTIME_LIB}")
endif()

# nlohmann/json
find_package(nlohmann_json REQUIRED)
message(STATUS "Found nlohmann_json")

# Find Emacs include path (for dynamic module support)
if(APPLE)
    # Try to find emacs-plus installation
    file(GLOB EMACS_PLUS_INCLUDE "/opt/homebrew/Cellar/emacs-plus/*/include")
    if(EMACS_PLUS_INCLUDE)
        list(GET EMACS_PLUS_INCLUDE 0 EMACS_INCLUDE_DIR)
        message(STATUS "Found emacs-plus include: ${EMACS_INCLUDE_DIR}")
    else()
        # Fall back to standard locations
        find_path(EMACS_INCLUDE_DIR
            NAMES emacs-module.h
            PATHS
                /usr/local/include
                /opt/homebrew/include
                /Applications/Emacs.app/Contents/Resources/include
        )
    endif()
else()
    find_path(EMACS_INCLUDE_DIR
        NAMES emacs-module.h
        PATHS
            /usr/local/include
            /usr/include
    )
endif()

if(NOT EMACS_INCLUDE_DIR)
    message(FATAL_ERROR "emacs-module.h not found. Please install Emacs with module support.")
endif()

message(STATUS "Found Emacs include: ${EMACS_INCLUDE_DIR}")

# Check for assets directory and download if needed
if(NOT EXISTS "${CMAKE_SOURCE_DIR}/assets")
    message(STATUS "Assets directory not found. Downloading from Hugging Face...")
    execute_process(
        COMMAND git clone https://huggingface.co/Supertone/supertonic assets
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        RESULT_VARIABLE ASSETS_RESULT
    )
    if(ASSETS_RESULT EQUAL 0)
        message(STATUS "Assets downloaded successfully")
    else()
        message(WARNING "Failed to download assets. You may need to run:\n"
                        "  git clone https://huggingface.co/Supertone/supertonic assets\n"
                        "in the project directory.")
    endif()
else()
    message(STATUS "Found assets directory")
endif()

# Build the Emacs dynamic module
add_library(dawa-tts-module MODULE
    dawa-tts-module.cpp
    lib/supertonic.cpp
)

# Set module properties
set_target_properties(dawa-tts-module PROPERTIES
    PREFIX ""
    SUFFIX ${MODULE_SUFFIX}
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}
)

# Include directories
target_include_directories(dawa-tts-module PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${EMACS_INCLUDE_DIR}
)

if(NOT onnxruntime_FOUND)
    target_include_directories(dawa-tts-module PRIVATE ${ONNXRUNTIME_INCLUDE_DIR})
endif()

# Link libraries
if(onnxruntime_FOUND)
    target_link_libraries(dawa-tts-module
        onnxruntime::onnxruntime
        nlohmann_json::nlohmann_json
    )
else()
    target_link_libraries(dawa-tts-module
        ${ONNXRUNTIME_LIB}
        nlohmann_json::nlohmann_json
    )
endif()

# Link C++ standard library explicitly on macOS
if(APPLE)
    target_link_libraries(dawa-tts-module c++)
endif()

# Apply platform-specific linker flags
target_link_options(dawa-tts-module PRIVATE ${MODULE_LINKER_FLAGS})

# Print build summary
message(STATUS "")
message(STATUS "========================================")
message(STATUS "dawa-tts CMake Configuration Summary")
message(STATUS "========================================")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C++ compiler: ${CMAKE_CXX_COMPILER}")
message(STATUS "C++ standard: C++${CMAKE_CXX_STANDARD}")
message(STATUS "Module output: ${CMAKE_SOURCE_DIR}/dawa-tts-module${MODULE_SUFFIX}")
message(STATUS "========================================")
message(STATUS "")
