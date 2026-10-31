#!/bin/bash
# 编译 llama-cpp-python，amd64 按 SSE4.2 基线（不带 BMI2/AVX）
#
# 关键点：CMAKE_ARGS 里带空格的 -D 值会被 scikit-build 按空格拆开，所以
# 编译器开关不能放 CMAKE_ARGS，必须用 CFLAGS/CXXFLAGS 环境变量传。
#
# 为什么连 BMI2 都要关：Pentium Silver J5005（Gemini Lake）只有 SSE4.2 + POPCNT，
# 没有 AVX、没有 BMI2。gcc 在默认 -march 下仍会发射 shlx（BMI2），加载模型即 SIGILL。
set -euo pipefail

if [ "${TARGETARCH:-amd64}" = "amd64" ]; then
  export CFLAGS="-O3 -march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-avx512f -mno-bmi -mno-bmi2 -mno-fma -mno-f16c"
  export CXXFLAGS="$CFLAGS"
  export CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_AVX512=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_SSE42=ON"
  echo "[build] amd64 基线编译"
else
  export CMAKE_ARGS="-DGGML_NATIVE=OFF"
  echo "[build] ${TARGETARCH:-arm64} 编译"
fi

echo "[build] CFLAGS=$CFLAGS"
/usr/local/bin/pip wheel --no-deps --wheel-dir /tmp/wheels "llama-cpp-python==${LLAMA_CPP_VERSION}"
/usr/local/bin/pip install --no-deps --target /app/.venv/lib/python3.13/site-packages /tmp/wheels/llama_cpp_python-*.whl
/usr/local/bin/pip install --no-deps --quiet --target /app/.venv/lib/python3.13/site-packages diskcache
rm -rf /tmp/wheels

# 校验：不许出现任何 AVX/AVX2/BMI2 指令
if [ "${TARGETARCH:-amd64}" = "amd64" ]; then
  echo "== 校验二进制里没有 AVX/AVX2/BMI2 指令 =="
  bad=0
  for f in /app/.venv/lib/python3.13/site-packages/llama_cpp/lib/*.so*; do
    n=$(objdump -d "$f" | grep -cE "%ymm|%zmm|vzeroupper|shlx|shrx|sarx" || true)
    echo "  $(basename "$f") 违规指令=$n"
    [ "$n" -eq 0 ] || bad=1
  done
  if [ "$bad" -ne 0 ]; then
    echo "!! 二进制含 AVX/BMI2 指令，在老 CPU（J5005）上会 SIGILL"
    exit 1
  fi
fi
