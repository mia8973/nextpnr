set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_AUTOMOC ON)

set(GUI_SOURCES
    application.cc
    application.h
    basewindow.cc
    basewindow.h
    designwidget.cc
    designwidget.h
    fpgaviewwidget.cc
    fpgaviewwidget.h
    line_editor.cc
    line_editor.h
    lineshader.cc
    lineshader.h
    rubytab.cc
    rubytab.h
    quadtree.h
    treemodel.cc
    treemodel.h
    worker.cc
    worker.h
    ${family}/mainwindow.cc
    ${family}/mainwindow.h
)

if (Qt6_FOUND)
    qt6_add_resources(GUI_QT_RESOURCES
        base.qrc
        ${family}/nextpnr.qrc
    )
else()
    qt5_add_resources(GUI_QT_RESOURCES
        base.qrc
        ${family}/nextpnr.qrc
    )
endif()

add_library(nextpnr-${target}-gui OBJECT
    ${GUI_SOURCES}
    ${GUI_QT_RESOURCES}
)

target_compile_definitions(nextpnr-${target}-gui PUBLIC
    QT_NO_KEYWORDS
)

target_include_directories(nextpnr-${target}-gui PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/${family}
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_include_directories(nextpnr-${target}-gui PRIVATE
    ${CMAKE_SOURCE_DIR}/frontend
    ${CMAKE_SOURCE_DIR}/json
    ${CMAKE_SOURCE_DIR}/3rdparty/QtPropertyBrowser/src
    ${CMAKE_SOURCE_DIR}/3rdparty/imgui
    ${CMAKE_SOURCE_DIR}/3rdparty/qtimgui
)

if (Qt6_FOUND)
    target_link_libraries(nextpnr-${target}-gui PUBLIC Qt6::Widgets)
    target_link_libraries(nextpnr-${target}-gui PRIVATE Qt6::OpenGL Qt6::OpenGLWidgets)
else()
    target_link_libraries(nextpnr-${target}-gui PUBLIC Qt5::Widgets)
    target_link_libraries(nextpnr-${target}-gui PRIVATE Qt5::OpenGL)
endif()

target_link_libraries(nextpnr-${target}-gui PRIVATE
    nextpnr-${target}-defs
    nextpnr_version
    QtPropertyBrowser
)

if (BUILD_RUBY)
    target_include_directories(nextpnr-${target}-gui PRIVATE
        ${MRUBY_INCLUDE_DIRS}
    )

    target_sources(nextpnr-${target}-gui PRIVATE
        ../3rdparty/imgui/imgui_widgets.cpp
        ../3rdparty/imgui/imgui_draw.cpp
        ../3rdparty/imgui/imgui.cpp
        ../3rdparty/imgui/imgui_demo.cpp
        ../3rdparty/qtimgui/ImGuiRenderer.cpp
        ../3rdparty/qtimgui/QtImGui.cpp
    )
endif()
