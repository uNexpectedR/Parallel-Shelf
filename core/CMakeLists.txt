cmake_minimum_required(VERSION 3.14)
project(ParallelShelfCoreModule LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT or ensure logos-module-builder is in your flake inputs.")
endif()

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" METADATA_JSON)
string(JSON MODULE_NAME GET ${METADATA_JSON} name)

logos_module(
    NAME ${MODULE_NAME}
    SOURCES
        src/parallel_shelf_core_impl.h
        src/parallel_shelf_core_impl.cpp
        src/file_read.h
        src/page_render.h
    INCLUDE_DIRS src
)

# Do not find_package Qt6 Pdf or WebEngine. Linking those into this
# dylib crash-loads logoscore on Mac Basecamp. pdftoppm is a runtime binary.
