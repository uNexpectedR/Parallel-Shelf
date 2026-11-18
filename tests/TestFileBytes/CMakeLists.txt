cmake_minimum_required(VERSION 3.16)
project(filebytesplugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Qml)

qt_add_plugin(filebytesplugin CLASS_NAME FileBytesPlugin
    ../../src/filebytes.cpp
    plugin.cpp
)

target_include_directories(filebytesplugin PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../../src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../core/src")
target_link_libraries(filebytesplugin PRIVATE Qt6::Core Qt6::Qml)

set_target_properties(filebytesplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
