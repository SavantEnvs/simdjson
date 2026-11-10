# Passed as -DCMAKE_PROJECT_INCLUDE: adds the mining harness without editing upstream's fuzz/CMakeLists.txt.
set(MAYHEM_HARNESS_DIR "${CMAKE_CURRENT_LIST_DIR}")
function(mayhem_add_harness)
  add_executable(fuzz_ondemand_atpointer "${MAYHEM_HARNESS_DIR}/fuzz_ondemand_atpointer.cpp")
  target_include_directories(fuzz_ondemand_atpointer PRIVATE "${CMAKE_SOURCE_DIR}/fuzz")
  target_link_libraries(fuzz_ondemand_atpointer PRIVATE simdjson-fuzzer)
  add_dependencies(all_fuzzers fuzz_ondemand_atpointer)
endfunction()
cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL mayhem_add_harness)
