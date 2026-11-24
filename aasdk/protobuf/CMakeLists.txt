cmake_minimum_required(VERSION 3.16)

#Android Auto Projection Protocol Library
project(aap_protobuf)
message(STATUS "AASDK ProtoBuf Library")

# Use versioning from parent project if available, otherwise use defaults
if(DEFINED LIBRARY_BUILD_MAJOR_RELEASE AND DEFINED LIBRARY_BUILD_MINOR_RELEASE AND DEFINED LIBRARY_BUILD_PATCH_RELEASE)
    # Use parent project versioning
    set(AAP_VERSION_MAJOR ${LIBRARY_BUILD_MAJOR_RELEASE})
    set(AAP_VERSION_MINOR ${LIBRARY_BUILD_MINOR_RELEASE}) 
    set(AAP_VERSION_PATCH ${LIBRARY_BUILD_PATCH_RELEASE})
    
    # Use parent project's version string if available
    if(DEFINED LIBRARY_VERSION_STRING)
        set(LIBRARY_BUILD_VERSION_STRING ${LIBRARY_VERSION_STRING})
    else()
        set(LIBRARY_BUILD_VERSION_STRING "${AAP_VERSION_MAJOR}.${AAP_VERSION_MINOR}.${AAP_VERSION_PATCH}")
    endif()
else()
    # Fallback to original versioning for standalone builds
    set(LIBRARY_BUILD_DATE "20241121")    # Binary Release Build Date
    set(LIBRARY_BUILD_MAJOR_RELEASE 4)        # Binary Release Build Number (increment if released on same day)
    set(LIBRARY_BUILD_MINOR_RELEASE 0)        # Binary Release Build Number (increment if released on same day)
    set(LIBRARY_BUILD_INCREMENTAL 0)    # Binary Build Version - Increment for Each Build
    set(LIBRARY_BUILD_VERSION_STRING "${LIBRARY_BUILD_MAJOR_RELEASE}.${LIBRARY_BUILD_MINOR_RELEASE}.${LIBRARY_BUILD_INCREMENTAL}+${LIBRARY_BUILD_DATE}")
endif()
set(AAP_PROTO_VERSION 1.6)          # Underlying AAP (Android Auto Projection Library Protocol)

set(CMAKE_CXX_STANDARD 17)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Default to Release mode unless overridden with -DCMAKE_BUILD_TYPE=Debug on cmake command
if(NOT CMAKE_BUILD_TYPE)
    message(STATUS "Forcing Release build type")
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build." FORCE)
    # Set the possible values of build type for cmake-gui
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release" "MinSizeRel" "RelWithDebInfo")
endif()

# Building on a Mac requires Abseil
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")  # macOS
    # macOS specific command
    message(STATUS "MacOS System Detected")
    find_package(protobuf REQUIRED CONFIG)
    find_package(absl)
    include(FindProtobuf)
else()
    # Linux specific command
    # OpenCruise fix: the original code found protobuf by hand (find_path / find_library / find_program into
    # PROTOBUF_PROTOC_EXECUTABLE), set Protobuf_FOUND itself and then include()d FindProtobuf. On the second
    # configure run the cached Protobuf_PROTOC_EXECUTABLE stayed empty, so the protobuf::protoc target was not
    # created and the generated build used the literal command "protobuf::protoc"
    # (make: "target pattern contains no '%'"). Use the normal find_package() instead:
    #  1) protobuf's own CMake package if installed (newer protobuf; brings its Abseil dependencies and protoc)
    #  2) otherwise CMake's FindProtobuf module (distribution packages such as libprotobuf-dev 3.21)
    # A build directory configured with the old code may hold an empty Protobuf_PROTOC_EXECUTABLE in its cache,
    # which stops find_program() from searching again. Drop it so that existing build directories recover.
    if(DEFINED CACHE{Protobuf_PROTOC_EXECUTABLE} AND NOT Protobuf_PROTOC_EXECUTABLE)
        unset(Protobuf_PROTOC_EXECUTABLE CACHE)
    endif()
    set(protobuf_MODULE_COMPATIBLE ON)   # the CMake package also provides protobuf_generate_cpp()
    find_package(Protobuf CONFIG QUIET)
    if(NOT Protobuf_FOUND)
        find_package(Protobuf MODULE)
    endif()
    # OpenCruise fix (cross builds such as Yocto): the target protobuf package is built without protoc, so its CMake package
    # has no protobuf::protoc target. When the build passes the host protoc in Protobuf_PROTOC_EXECUTABLE, use that one
    # (and prefer it over a protoc from the package, which would be a binary for the target and could not run on the host).
    if(Protobuf_FOUND AND Protobuf_PROTOC_EXECUTABLE AND EXISTS "${Protobuf_PROTOC_EXECUTABLE}")
        if(NOT TARGET protobuf::protoc)
            add_executable(protobuf::protoc IMPORTED)
        endif()
        set_target_properties(protobuf::protoc PROPERTIES
            IMPORTED_LOCATION "${Protobuf_PROTOC_EXECUTABLE}"
            IMPORTED_LOCATION_RELEASE "${Protobuf_PROTOC_EXECUTABLE}"
            IMPORTED_LOCATION_NOCONFIG "${Protobuf_PROTOC_EXECUTABLE}")
    endif()
    if(NOT Protobuf_FOUND OR NOT TARGET protobuf::protoc)
        message(FATAL_ERROR "Protobuf not found. Please install libprotobuf-dev and protobuf-compiler")
    endif()
    get_target_property(_aap_protoc protobuf::protoc IMPORTED_LOCATION_RELEASE)
    if(NOT _aap_protoc)
        get_target_property(_aap_protoc protobuf::protoc IMPORTED_LOCATION)
    endif()
    message(STATUS "Found Protobuf ${Protobuf_VERSION} (protoc: ${_aap_protoc})")
endif()

# Turn off Path Appending
set(PROTOBUF_GENERATE_CPP_APPEND_PATH OFF)

# Locate all proto files
file(GLOB_RECURSE source_proto_files ${CMAKE_CURRENT_SOURCE_DIR}/*.proto)

# Compile ProtoBuf files
protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS ${source_proto_files})

# Generate Library
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")  # macOS
    message(NOTICE "Configuring STATIC Library for MacOS")
    add_library(aap_protobuf STATIC ${PROTO_SRCS} ${PROTO_HDRS})
else()
    message(NOTICE "Configuring SHARED Library")
    add_library(aap_protobuf SHARED ${PROTO_SRCS} ${PROTO_HDRS})
endif()

# OpenCruise fix: link the imported target when it exists (it carries protobuf's include dirs and, for newer
# protobuf, its Abseil dependencies); fall back to the plain library list otherwise
if(TARGET protobuf::libprotobuf)
    target_link_libraries(aap_protobuf PUBLIC protobuf::libprotobuf)
else()
    target_link_libraries(aap_protobuf PUBLIC ${PROTOBUF_LIBRARIES})
endif()
include_directories(
        ${CMAKE_CURRENT_BINARY_DIR}
        ${CMAKE_CURRENT_BINARY_DIR}/aap_protobuf
        ${PROTOBUF_INCLUDE_DIR}
)

set(LIBRARY_BUILD_VERSION_STRING "${LIBRARY_BUILD_MAJOR_RELEASE}.${LIBRARY_BUILD_MINOR_RELEASE}.${LIBRARY_BUILD_INCREMENTAL}+${LIBRARY_BUILD_DATE}")
message(STATUS "aap_protobuf Project Version: ${LIBRARY_BUILD_VERSION_STRING}")

# Set version properties
if(DEFINED LIBRARY_BUILD_MAJOR_RELEASE)
    set_target_properties(aap_protobuf
            PROPERTIES
            VERSION ${LIBRARY_BUILD_VERSION_STRING}
            SOVERSION ${LIBRARY_BUILD_MAJOR_RELEASE})
else()
    set_target_properties(aap_protobuf
            PROPERTIES
            VERSION ${LIBRARY_BUILD_VERSION_STRING}
            SOVERSION 4)
endif()

# Install rules with component assignment for packaging
install(TARGETS aap_protobuf
        EXPORT aap_protobufTargets
        LIBRARY DESTINATION lib COMPONENT runtime
        ARCHIVE DESTINATION lib COMPONENT runtime
        RUNTIME DESTINATION bin COMPONENT runtime
        INCLUDES DESTINATION include
)

target_include_directories(aap_protobuf
        PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}>
        $<INSTALL_INTERFACE:include/aap_protobuf>
)

# Install headers explicitly with component assignment
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/aap_protobuf
        DESTINATION include
        COMPONENT development
        FILES_MATCHING PATTERN "*.h")

# Export the targets to a script
install(EXPORT aap_protobufTargets
        FILE aap_protobufTargets.cmake
        NAMESPACE AAPProto::
        DESTINATION lib/cmake/aap_protobuf
        COMPONENT development
)

# Create a Config file for FindPackage
include(CMakePackageConfigHelpers)
write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/aap_protobufConfigVersion.cmake"
        VERSION 1.0
        COMPATIBILITY AnyNewerVersion
)

configure_package_config_file(Config.cmake.in
        "${CMAKE_CURRENT_BINARY_DIR}/aap_protobufConfig.cmake"
        INSTALL_DESTINATION lib/cmake/aap_protobuf
)

# Install the config files
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/aap_protobufConfigVersion.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/aap_protobufConfig.cmake"
        DESTINATION lib/cmake/aap_protobuf
        COMPONENT development)


