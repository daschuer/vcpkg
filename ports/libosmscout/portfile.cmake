vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO Framstag/libosmscout
    REF c81e1d9a0f69cc5b93588dbe330b2af587162c5f
    SHA512 d6ddbc49dd40b1f938ae2cd1ea9342cab0a52db46bf7ed6716111a91d0a38acba12ff2e273d457db51fc240d578a5b849af77b53e600482cf52c3b22306f8c45
    HEAD_REF master
)

if(VCPKG_TARGET_IS_WINDOWS OR VCPKG_TARGET_IS_UWP)
	vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
		cairo OSMDCOUT_BUILD_MAP_CAIRO
		directx OSMDCOUT_BUILD_MAP_DIRECTX
		gdi OSMDCOUT_BUILD_MAP_GDI
		svg OSMDCOUT_BUILD_MAP_SVG
	)
else()
	vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
		cairo OSMDCOUT_BUILD_MAP_CAIRO
		svg OSMDCOUT_BUILD_MAP_SVG
	)
	list(APPEND FEATURE_OPTIONS -DOSMDCOUT_BUILD_MAP_DIRECTX=OFF -DOSMDCOUT_BUILD_MAP_GDI=OFF)
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    WINDOWS_USE_MSBUILD
    OPTIONS
        -DOSMSCOUT_BUILD_DEMOS=OFF
        -DOSMSCOUT_BUILD_TOOL_DUMPDATA=OFF
        -DOSMSCOUT_BUILD_TOOL_IMPORT=ON
        -DOSMSCOUT_BUILD_TOOL_OSMSCOUT2=OFF
        -DOSMSCOUT_BUILD_TOOL_OSMSCOUTOPENGL=OFF
        -DOSMSCOUT_BUILD_TOOL_PUBLICTRANSPORTMAP=OFF
        -DOSMSCOUT_BUILD_TOOL_STYLEEDITOR=OFF
        -DOSMSCOUT_BUILD_EXTERN_MATLAB=OFF
        -DOSMSCOUT_BUILD_TESTS=OFF
        -DOSMDCOUT_BUILD_MAP_QT=OFF
        ${FEATURE_OPTIONS}
)

vcpkg_cmake_install()
vcpkg_copy_tools(TOOL_NAMES Import AUTO_CLEAN)
vcpkg_cmake_config_fixup(CONFIG_PATH share/cmake/libosmscout)

file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")
file(REMOVE "${CURRENT_PACKAGES_DIR}/debug/bin/BasemapImport.exe")
file(REMOVE "${CURRENT_PACKAGES_DIR}/bin/BasemapImport.exe")
