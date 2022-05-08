message(WARNING "qtkeychain is a third-party extension to Qt and is not affiliated with The Qt Company")

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO daschuer/qtkeychain
    # 0.13.2 plus two commits, for a CMake export target fix
    REF 07452a8ecb4f36bdcd8fbd56b947a95b3573bd58
    SHA512 40642c201134fbf20420bed934fc69c5dc0e7a9d1b4daa0638bea827b01efc0149a2a114974496608db763c100a5d6cca1f78c3c49cad625093381b69e8df4a8
    HEAD_REF master
)

# Opportunity to build without dependency on qt5-tools/qt5-declarative
set(BUILD_TRANSLATIONS OFF)
if("translations" IN_LIST FEATURES)
    set(BUILD_TRANSLATIONS ON)
endif()

vcpkg_cmake_configure(
    DISABLE_PARALLEL_CONFIGURE
    SOURCE_PATH ${SOURCE_PATH}
    OPTIONS
        -DBUILD_WITH_QT6=OFF
        -DBUILD_TEST_APPLICATION=OFF
        -DBUILD_TRANSLATIONS=${BUILD_TRANSLATIONS}
)
vcpkg_cmake_install()

vcpkg_copy_pdbs()
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/Qt5Keychain PACKAGE_NAME Qt5Keychain)

# Remove unneeded dirs
file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

# Handle copyright
file(INSTALL "${SOURCE_PATH}/COPYING" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
