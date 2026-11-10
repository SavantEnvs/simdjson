#!/usr/bin/env bash
# Mining build (BASE of the On-Demand at_pointer fix): the mayhem/fuzz_ondemand_atpointer.cpp
# libFuzzer harness + a standalone reproducer, plus the unit tests that mayhem/test.sh runs. Idempotent and air-gapped: CPM resolves its downloads
# (CPM.cmake, simdjson-data, counters, cxxopts) from CPM_SOURCE_CACHE, filled by the Dockerfile.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${CPM_SOURCE_CACHE:=/opt/toolchains/cpm}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS CPM_SOURCE_CACHE

cd "$SRC"
M="$SRC/mayhem"
FUZZERS="ondemand_atpointer"
HARNESS_CMAKE="-DCMAKE_PROJECT_INCLUDE=$M/harness.cmake"

# cmake reads CC/CXX from the environment; passing -DCMAKE_*_COMPILER=<name> would invalidate
# the cache on re-run (the cache stores the resolved path).
COMMON=(-G Ninja
        -DSIMDJSON_DEVELOPER_MODE=ON -DBUILD_SHARED_LIBS=OFF -DSIMDJSON_COMPETITION=Off
        -DSIMDJSON_GOOGLE_BENCHMARKS=Off)

# 1) lsan_off hook (ASan stays on; only leak detection is disabled).
mkdir -p "$M/obj" "$M/bin"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$M/lsan_off.cc" -o "$M/obj/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$M/obj/standalone_main.o"

# 2) Sanitized, DWARF-3 fuzz harnesses: libFuzzer engine (like OSS-Fuzz's fuzz/ossfuzz.sh) ...
# -fsanitize=fuzzer-no-link puts SanCov on the library and harness compiles (as fuzz/CMakeLists.txt
# requires); the engine itself is only linked via SIMDJSON_FUZZ_LDFLAGS. Without it: 0 edges.
FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"
# Same define as upstream's fuzz/build_like_ossfuzz.sh: padded_string(size_t) then refuses >1 MiB
# instead of the harness's arbitrary size_t OOMing the run.
FUZZ_DEFS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
FUZZ_FLAGS="$FLAGS -fsanitize=fuzzer-no-link $FUZZ_DEFS"
cmake -S "$SRC" -B "$M/build-fuzz" "${COMMON[@]}" -DCMAKE_BUILD_TYPE=Debug \
  -DSIMDJSON_ENABLE_FUZZING=On -DSIMDJSON_FUZZ_LINKMAIN=Off -DSIMDJSON_DISABLE_DEPRECATED_API=On "$HARNESS_CMAKE" \
  "-DSIMDJSON_FUZZ_LDFLAGS=$LIB_FUZZING_ENGINE;$M/obj/lsan_off.o" \
  "-DCMAKE_C_FLAGS=$FUZZ_FLAGS" "-DCMAKE_CXX_FLAGS=$FUZZ_FLAGS" \
  "-DCMAKE_C_FLAGS_DEBUG=-O1" "-DCMAKE_CXX_FLAGS_DEBUG=-O1" \
  "-DCMAKE_EXE_LINKER_FLAGS=$FLAGS"
cmake --build "$M/build-fuzz" --target fuzz_ondemand_atpointer -j"$MAYHEM_JOBS"

# ... and the project's own run-once file driver (fuzz/main.cpp) for the -standalone reproducers.
cmake -S "$SRC" -B "$M/build-fuzz-standalone" "${COMMON[@]}" -DCMAKE_BUILD_TYPE=Debug \
  -DSIMDJSON_ENABLE_FUZZING=On -DSIMDJSON_FUZZ_LINKMAIN=On -DSIMDJSON_DISABLE_DEPRECATED_API=On "$HARNESS_CMAKE" \
  "-DCMAKE_C_FLAGS=$FLAGS $FUZZ_DEFS" "-DCMAKE_CXX_FLAGS=$FLAGS $FUZZ_DEFS" \
  "-DCMAKE_C_FLAGS_DEBUG=-O1" "-DCMAKE_CXX_FLAGS_DEBUG=-O1" \
  "-DCMAKE_EXE_LINKER_FLAGS=$FLAGS $M/obj/lsan_off.o"
cmake --build "$M/build-fuzz-standalone" --target fuzz_ondemand_atpointer -j"$MAYHEM_JOBS"

for n in $FUZZERS; do
  cp -f "$M/build-fuzz/fuzz_$n" "$M/bin/fuzz_$n"
  cp -f "$M/build-fuzz-standalone/fuzz_$n" "$M/bin/fuzz_$n-standalone"
done

# 3) The test suite, NORMAL flags (no sanitizers), for mayhem/test.sh.
TESTS=$(grep -v '^#' "$M/tests.list" | awk -F'\t' 'NF{n=split($1,a,"/"); printf "%s ", a[n]}')
cmake -S "$SRC" -B "$M/build-tests" "${COMMON[@]}" -DCMAKE_BUILD_TYPE=Release -DSIMDJSON_ENABLE_FUZZING=Off \
  "-DCMAKE_C_FLAGS=$COVERAGE_FLAGS" "-DCMAKE_CXX_FLAGS=$COVERAGE_FLAGS"
cmake --build "$M/build-tests" --target $TESTS -j"$MAYHEM_JOBS"
