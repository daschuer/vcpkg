
if ("${TARGET_TRIPLET}" STREQUAL ${HOST_TRIPLET}) 
    # first path 
    # This creates packages/qt5-host-tools_${TARGET_TRIPLET}
    message(STATUS "creating a package from ${CURRENT_HOST_INSTALLED_DIR}/tools/qt5")
    file(COPY "${CURRENT_HOST_INSTALLED_DIR}/tools/qt5/" DESTINATION "${CURRENT_PACKAGES_DIR}/tools/qt5/")
else()
    # crosscompiling 
    message(FATAL_ERROR "qt5-host-tools can only be installed for the host")
endif()
