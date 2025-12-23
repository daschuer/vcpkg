vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO shibatch/sleef
    REF 3.9.0-40-g75f80b3
    SHA512 d2dd887b376cc3cedf83da502f9add6c9fa83a02066903a1462e974ca8070f27a1dd8f1deb0d8ff5d8945e00e85e856c62b09067746c32f993b2f633f0a9561a
    HEAD_REF master
    PATCHES
        export-link-libs.diff
        sleefdft.pc.diff
)

vcpkg_check_features(OUT_FEATURE_OPTIONS options
    FEATURES
        dft     SLEEF_BUILD_DFT
        dft     SLEEF_ENFORCE_DFT
)

if(VCPKG_CROSSCOMPILING)
    list(APPEND options "-DNATIVE_BUILD_DIR=${CURRENT_HOST_INSTALLED_DIR}/manual-tools/${PORT}")
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${options}
        -DSLEEF_BUILD_LIBM=ON
        -DSLEEF_BUILD_QUAD=ON
        -DSLEEF_BUILD_TESTS=OFF
        -DSLEEF_ENABLE_TESTER4=OFF
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/sleef)
vcpkg_fixup_pkgconfig()

if(NOT VCPKG_CROSSCOMPILING)
    set(tools mkrename qmkrename mkalias mkdisp qmkdisp)
    if("dft" IN_LIST FEATURES)
        list(APPEND tools mkdispatch mkunroll)
    endif()
    vcpkg_copy_tools(
        TOOL_NAMES ${tools}
        SEARCH_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/bin"
        DESTINATION "${CURRENT_PACKAGES_DIR}/manual-tools/${PORT}/bin"
        AUTO_CLEAN)
endif()    

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt")

