cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# --- Rust Build Integration ---
set(RUST_PROJECT_DIR "${CMAKE_SOURCE_DIR}/../rust_core")
set(RUST_TARGET_DIR "${RUST_PROJECT_DIR}/target")
set(RUST_LIB_NAME "mxenc_core.dll")

if(CMAKE_BUILD_TYPE MATCHES "Debug")
  set(RUST_BUILD_TYPE "release")
  set(RUST_CARGO_FLAG "--release")
else()
  set(RUST_BUILD_TYPE "release")
  set(RUST_CARGO_FLAG "--release")
endif()

set(RUST_LIB_PATH "${RUST_TARGET_DIR}/${RUST_BUILD_TYPE}/${RUST_LIB_NAME}")

# Build Rust library
add_custom_command(
  OUTPUT ${RUST_LIB_PATH}
  COMMAND cargo build ${RUST_CARGO_FLAG}
  WORKING_DIRECTORY ${RUST_PROJECT_DIR}
  VERBATIM
)

# Create a target to trigger the build
add_custom_target(rust_build ALL DEPENDS ${RUST_LIB_PATH})
add_dependencies(${BINARY_NAME} rust_build)

# Copy DLL to output directory for running
add_custom_command(
  TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    ${RUST_LIB_PATH}
    $<TARGET_FILE_DIR:${BINARY_NAME}>/${RUST_LIB_NAME}
)
