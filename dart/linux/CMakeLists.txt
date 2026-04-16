cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

set(BINARY_NAME "uniclient")
set(APPLICATION_ID "com.uniclient.app")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Configure build options from the CMake invocation.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O2>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and target platform.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(APPINDICATOR IMPORTED_TARGET ayatana-appindicator3-0.1)

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

if(APPINDICATOR_FOUND)
  add_definitions(-DHAVE_APPINDICATOR)
endif()

# Application build target.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
if(APPINDICATOR_FOUND)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::APPINDICATOR)
endif()

add_dependencies(${BINARY_NAME} flutter_assemble)

# Generated plugin build rules.
include(flutter/generated_plugins.cmake)

# === Installation ===
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${RUNTIME_BUNDLE_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Copy the native assets.
set(NATIVE_ASSETS_DIR "${CMAKE_CURRENT_BINARY_DIR}/native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Install the app icon.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/uniclient.png"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid stale data.
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/flutter_assets\")
  " COMPONENT Runtime)
install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/flutter_assets"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Bundle appindicator shared libraries into lib/ for runtime.
# We install the versioned .so files (e.g. .so.1) that match the DT_NEEDED
# entries, resolving the real file but keeping the soname as the filename.
if(APPINDICATOR_FOUND)
  set(_APPINDICATOR_SONAMES
    "libayatana-appindicator3.so.1"
    "libayatana-indicator3.so.7"
    "libayatana-ido3-0.4.so.0"
    "libdbusmenu-glib.so.4"
    "libdbusmenu-gtk3.so.4"
  )
  foreach(_soname ${_APPINDICATOR_SONAMES})
    # Extract the base library name (e.g. "ayatana-appindicator3") for find_library.
    string(REGEX REPLACE "^lib" "" _bare "${_soname}")
    string(REGEX REPLACE "\\.so.*" "" _bare "${_bare}")
    find_library(_found_lib "${_bare}" HINTS ${APPINDICATOR_LIBRARY_DIRS})
    if(_found_lib)
      get_filename_component(_lib_dir "${_found_lib}" DIRECTORY)
      set(_versioned "${_lib_dir}/${_soname}")
      if(EXISTS "${_versioned}")
        get_filename_component(_real "${_versioned}" REALPATH)
        install(FILES "${_real}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
          RENAME "${_soname}" COMPONENT Runtime)
      endif()
    endif()
    unset(_found_lib CACHE)
  endforeach()
endif()

# Install the AOT library (if applicable).
if(NOT("${AOT_LIBRARY}" STREQUAL ""))
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
