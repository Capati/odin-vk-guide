cmake_minimum_required(VERSION 3.5.0)
project(engine VERSION 0.1.0 LANGUAGES C CXX)

find_package(Vulkan REQUIRED FATAL_ERROR)

include(FetchContent)

set(_vulkanmemoryallocator_git_tag v3.0.1)

message(STATUS "Populating build dependency: VulkanMemoryAllocator")
FetchContent_Populate(VulkanMemoryAllocator
  GIT_REPOSITORY https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator
  GIT_SHALLOW TRUE GIT_TAG ${_vulkanmemoryallocator_git_tag}
  UPDATE_DISCONNECTED ${THIRD_PARTY_UPDATE_DISCONNECTED}
  QUIET
)

if(NOT EXISTS ${vulkanmemoryallocator_BINARY_DIR}/vk_mem_alloc.cc)
  file(WRITE ${vulkanmemoryallocator_BINARY_DIR}/vk_mem_alloc.cc
        "#define VMA_IMPLEMENTATION\n#include \"vk_mem_alloc.h\"")
endif()

add_library(vma ${vulkanmemoryallocator_BINARY_DIR}/vk_mem_alloc.cc)

add_custom_command(
	TARGET vma PRE_BUILD
	COMMAND ${CMAKE_COMMAND} -E copy
		${vulkanmemoryallocator_SOURCE_DIR}/include/vk_mem_alloc.h
		${vulkanmemoryallocator_BINARY_DIR}/vk_mem_alloc.h)

target_include_directories(vma
  PUBLIC
    ${vulkanmemoryallocator_SOURCE_DIR}/src
    ${VulkanHeaders_INCLUDE_DIR}
)
target_link_libraries(vma PUBLIC Vulkan::Vulkan)

# Build the library with dynamically linked and statically linked off.
# We are passing the pointers to vma manually.
add_compile_definitions(VMA_STATIC_VULKAN_FUNCTIONS=0)
add_compile_definitions(VMA_DYNAMIC_VULKAN_FUNCTIONS=0)

target_compile_definitions(vma
  PUBLIC
    $<$<PLATFORM_ID:Windows>:WIN32_LEAN_AND_MEAN>
  PRIVATE
    $<$<PLATFORM_ID:Linux>:
		VK_USE_PLATFORM_XLIB_KHR
		VK_USE_PLATFORM_XLIB_XRANDR_EXT
		VK_USE_PLATFORM_XCB_KHR
		VK_USE_PLATFORM_XCB_XRANDR_EXT
		VK_USE_PLATFORM_WAYLAND_KHR>
    $<$<PLATFORM_ID:Windows>:VK_USE_PLATFORM_WIN32_KHR>
    $<$<PLATFORM_ID:Darwin>:VK_USE_PLATFORM_MACOS_MVK>
)
