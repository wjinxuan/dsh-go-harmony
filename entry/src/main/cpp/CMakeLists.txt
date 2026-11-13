cmake_minimum_required(VERSION 3.16)
project(dsh_local LANGUAGES CXX)

get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
set(NODE_HEADERS "${PROJECT_ROOT}/runtime/.node/include/node")
set(NODE_LIBS "${PROJECT_ROOT}/entry/libs/${OHOS_ARCH}")
if(NOT EXISTS "${PROJECT_ROOT}/runtime/.node/prepared" OR
   NOT EXISTS "${NODE_HEADERS}/node.h" OR
   NOT EXISTS "${NODE_LIBS}/libnode.so" OR
   NOT EXISTS "${NODE_LIBS}/libc++_shared.so")
  message(FATAL_ERROR "Run ./runtime/prepare-node.sh before building the local engine.")
endif()

add_library(node_runtime SHARED IMPORTED)
set_target_properties(node_runtime PROPERTIES IMPORTED_LOCATION "${NODE_LIBS}/libnode.so")
add_library(node_cxx SHARED IMPORTED)
set_target_properties(node_cxx PROPERTIES IMPORTED_LOCATION "${NODE_LIBS}/libc++_shared.so")

add_library(dshlocal SHARED local_engine.cpp node_engine.cpp)
set_target_properties(dshlocal PROPERTIES SKIP_BUILD_RPATH TRUE)
target_compile_features(dshlocal PRIVATE cxx_std_20)
# ArkTS and Node have separate N-API headers with overlapping C symbols.
set_source_files_properties(node_engine.cpp PROPERTIES COMPILE_OPTIONS "-isystem;${NODE_HEADERS}")
target_link_options(dshlocal PRIVATE -nostdlib++ -Wl,--no-undefined)
target_link_libraries(dshlocal PRIVATE libace_napi.z.so node_runtime node_cxx libhilog_ndk.z.so)
