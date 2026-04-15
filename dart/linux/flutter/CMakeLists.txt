# This file controls Flutter-level build steps. It should not be edited.
cmake_minimum_required(VERSION 3.13)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

# Configuration provided via flutter tool.
include(${EPHEMERAL_DIR}/generated_config.cmake)

# TODO: Move the rest of this into files in ephemeral. See
# https://github.com/flutter/flutter/issues/57146.
set(WRAPPER_ROOT "${EPHEMERAL_DIR}/cpp_client_wrapper")

# Set fallback configurations for older versions of the flutter tool.
if(NOT DEFINED FLUTTER_TARGET_PLATFORM)
  set(FLUTTER_TARGET_PLATFORM "linux-x64")
endif()

# === Flutter Library ===
set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/libflutter_linux_gtk.so")

# Published to parent scope for install step.
set(FLUTTER_LIBRARY "${FLUTTER_LIBRARY}" PARENT_SCOPE)
set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${PROJECT_DIR}" PARENT_SCOPE)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC -pthread")

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET glib-2.0)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)

add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "${EPHEMERAL_DIR}"
)
target_link_libraries(flutter INTERFACE "${FLUTTER_LIBRARY}")
target_link_libraries(flutter INTERFACE
  PkgConfig::GTK
  PkgConfig::GLIB
  PkgConfig::GIO
)

# === Wrapper ===
list(APPEND CPP_WRAPPER_SOURCES_CORE
  "${WRAPPER_ROOT}/core_implementations.cc"
  "${WRAPPER_ROOT}/standard_codec.cc"
)

list(APPEND CPP_WRAPPER_SOURCES_PLUGIN
  "${WRAPPER_ROOT}/plugin_registrar.cc"
)

list(APPEND CPP_WRAPPER_SOURCES_APP
  "${WRAPPER_ROOT}/flutter_engine.cc"
  "${WRAPPER_ROOT}/flutter_view_controller.cc"
)

# Wrapper sources needed for a generated plugin.
add_library(flutter_wrapper_plugin STATIC ${CPP_WRAPPER_SOURCES_CORE} ${CPP_WRAPPER_SOURCES_PLUGIN})
apply_standard_settings(flutter_wrapper_plugin)
set_target_properties(flutter_wrapper_plugin PROPERTIES
  POSITION_INDEPENDENT_CODE ON)
# Relax warnings for Flutter SDK C++ wrapper code (GCC 15+ pedantic warnings).
target_compile_options(flutter_wrapper_plugin PRIVATE -Wno-error=pessimizing-move)
target_link_libraries(flutter_wrapper_plugin PUBLIC flutter)
target_include_directories(flutter_wrapper_plugin PUBLIC
  "${WRAPPER_ROOT}/include"
)
add_dependencies(flutter_wrapper_plugin flutter_assemble)

# Wrapper sources needed for the runner (not used by Linux GTK runner,
# but defined for completeness — only built if sources exist).
if(EXISTS "${WRAPPER_ROOT}/flutter_engine.cc" AND EXISTS "${WRAPPER_ROOT}/flutter_view_controller.cc")
  add_library(flutter_wrapper_app STATIC ${CPP_WRAPPER_SOURCES_CORE} ${CPP_WRAPPER_SOURCES_APP})
  apply_standard_settings(flutter_wrapper_app)
  target_compile_options(flutter_wrapper_app PRIVATE -Wno-error=pessimizing-move -Wno-error)
  target_link_libraries(flutter_wrapper_app PUBLIC flutter)
  target_include_directories(flutter_wrapper_app PUBLIC
    "${WRAPPER_ROOT}/include"
  )
  add_dependencies(flutter_wrapper_app flutter_assemble)
endif()

# === Flutter tool backend ===
# NixOS workaround: Flutter's tool_backend.sh fails because nix store uses
# symlinks for engine artifacts and unpackDesktopArtifacts rejects them.
# When FLUTTER_SKIP_ASSEMBLE is set, we use a no-op instead.
# Dart compilation and asset bundling are done manually before CMake.
if(DEFINED ENV{FLUTTER_SKIP_ASSEMBLE})
  add_custom_command(
    OUTPUT flutter_assemble_phony_
    COMMAND ${CMAKE_COMMAND} -E echo "Skipping flutter_assemble (NixOS manual build
  VERBATIM)"
    VERBATIM
  )
else()
  add_custom_command(
    OUTPUT flutter_assemble_phony_
    COMMAND ${CMAKE_COMMAND} -E
      env ${FLUTTER_TOOL_ENVIRONMENT}
      "${FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.sh"
      ${FLUTTER_TARGET_PLATFORM} ${CMAKE_BUILD_TYPE}
    VERBATIM
  )
endif()
add_custom_target(flutter_assemble DEPENDS flutter_assemble_phony_)
