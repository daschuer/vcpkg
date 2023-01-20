# Automatically generated by scripts/boost/generate-ports.ps1

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO boostorg/optional
    REF boost-1.81.0
    SHA512 68328b99373e4b8697be9cb4d7e5f69e6acf02606f37896f0f2e47304223ad6c9a801b6fa94bdddaa010482b190b854cda1760b0fcf55458e56d147123b88925
    HEAD_REF master
)

include(${CURRENT_INSTALLED_DIR}/share/boost-vcpkg-helpers/boost-modular-headers.cmake)
boost_modular_headers(SOURCE_PATH ${SOURCE_PATH})
