#!/bin/bash
# 编译 llama-cpp-python，按 ISA 基线分档（ISA=sse42 | avx2）
#
# 关键点：
# 1) CMAKE_ARGS 里带空格的 -D 值会被 scikit-build 按空格拆开，编译器开关必须走
#    CFLAGS/CXXFLAGS 环境变量，否则静默失效。
# 2) GGML_BMI2 是独立开关且默认 ON，任何 AVX 开关都管不到它；ggml-cpu 的
#    CMakeLists 会据此加 -mbmi2，编出 shlx，在没有 BMI2 的老 CPU 上 SIGILL。
# 3) Pentium Silver J5005（Gemini Lake）只有 SSE4.2 + POPCNT：无 AVX、AVX2、
#    FMA、F16C、BMI2。sse42 档就是给它用的。
set -euo pipefail

ISA="${ISA:-sse42}"
ARCH="${TARGETARCH:-amd64}"

if [ "$ARCH" != "amd64" ]; then
  # arm64：NEON 由 llama.cpp 自己处理，只要别嗅探构建机
  export CMAKE_ARGS="-DGGML_NATIVE=OFF"
  echo "[build] ${ARCH} 编译"
else
  case "$ISA" in
    sse42)
      export CFLAGS="-O3 -march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-avx512f -mno-bmi -mno-bmi2 -mno-fma -mno-f16c"
      export CXXFLAGS="$CFLAGS"
      export CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_BMI2=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_AVX512=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_SSE42=ON"
      FORBID='%ymm|%zmm|vzeroupper|shlx|shrx|sarx'
      ;;
    avx2)
      export CFLAGS="-O3 -mtune=generic"
      export CXXFLAGS="$CFLAGS"
      export CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_BMI2=ON -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_AVX512=OFF -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_SSE42=ON"
      FORBID='%zmm'
      ;;
    *)
      echo "!! 未知 ISA: $ISA（只支持 sse42 / avx2）"; exit 1 ;;
  esac
  echo "[build] amd64 ISA=$ISA"
  echo "[build] CFLAGS=${CFLAGS:-}"
fi

/usr/local/bin/pip wheel --no-deps --wheel-dir /tmp/wheels "llama-cpp-python==${LLAMA_CPP_VERSION}"
/usr/local/bin/pip install --no-deps --target /app/.venv/lib/python3.13/site-packages /tmp/wheels/llama_cpp_python-*.whl
/usr/local/bin/pip install --no-deps --quiet --target /app/.venv/lib/python3.13/site-packages diskcache
rm -rf /tmp/wheels

# 校验：不许出现超出该档位的指令
if [ "$ARCH" = "amd64" ]; then
  echo "== 校验二进制（禁止: $FORBID）=="
  bad=0
  for f in /app/.venv/lib/python3.13/site-packages/llama_cpp/lib/*.so*; do
    n=$(objdump -d "$f" | grep -cE "$FORBID" || true)
    echo "  $(basename "$f") 违规=$n"
    [ "$n" -eq 0 ] || bad=1
  done
  if [ "$bad" -ne 0 ]; then
    echo "!! 二进制超出 $ISA 基线，会在目标 CPU 上 SIGILL"
    exit 1
  fi
fi
