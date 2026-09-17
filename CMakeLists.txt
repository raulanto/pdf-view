cmake_minimum_required(VERSION 3.24)
project(pdf_view VERSION 0.1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml Test)
qt_policy(SET QTP0001 NEW)
find_package(PkgConfig REQUIRED)
pkg_check_modules(POPPLER REQUIRED IMPORTED_TARGET poppler-qt6)
qt_add_library(pdfbridge SHARED)
qt_add_qml_module(pdfbridge URI PdfView VERSION 1.0
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/PdfView
    SOURCES src/pdfpage.h src/pdfpage.cpp src/sandbox.h)
target_include_directories(pdfbridge PRIVATE src)
target_link_libraries(pdfbridge PRIVATE Qt6::Quick)
add_executable(pdf-worker src/worker.cpp)
target_link_libraries(pdf-worker PRIVATE Qt6::Gui PkgConfig::POPPLER)
find_program(CARGO_EXECUTABLE cargo REQUIRED)
add_custom_target(theme-service ALL
    COMMAND ${CARGO_EXECUTABLE} build --locked --offline --release
        --manifest-path ${CMAKE_SOURCE_DIR}/rust/theme/Cargo.toml
        --target-dir ${CMAKE_BINARY_DIR}/rust
    BYPRODUCTS ${CMAKE_BINARY_DIR}/rust/release/pdf-view-theme
    COMMENT "Building Rust theme service")
include(CTest)
if(BUILD_TESTING)
    add_test(NAME theme-unit COMMAND ${CARGO_EXECUTABLE} test --locked --offline
        --manifest-path ${CMAKE_SOURCE_DIR}/rust/theme/Cargo.toml --target-dir ${CMAKE_BINARY_DIR}/rust)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    add_test(NAME theme-reload COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/theme_reload.py ${CMAKE_BINARY_DIR}/rust/release/pdf-view-theme)
    add_executable(sandbox-probe tests/probe.cpp)
    add_executable(pdf-tests tests/test.cpp src/pdfpage.cpp src/pdfpage.h src/sandbox.h)
    target_include_directories(pdf-tests PRIVATE src)
    target_link_libraries(pdf-tests PRIVATE Qt6::Quick Qt6::Test)
    add_test(NAME integration COMMAND pdf-tests)
    set_tests_properties(integration PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=;QT_QUICK_CONTROLS_STYLE=Basic;PDF_VIEW_WORKER=${CMAKE_BINARY_DIR}/pdf-worker;PDF_VIEW_PROBE=${CMAKE_BINARY_DIR}/sandbox-probe")
endif()
