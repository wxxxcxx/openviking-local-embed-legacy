# OpenViking + 本地 GGUF embedding（llama-cpp-python）
#
# 官方镜像不含 llama-cpp-python，官方预编译轮子链接 musl，在这套 Debian 镜像上
# import 会失败。所以从源码编译，编完删工具链。
#
# 指令集：amd64 必须按 SSE4.2 基线编译。
#   Pentium Silver J5005（Gemini Lake）只有 SSE4.2 —— 没有 AVX，也没有 AVX2/FMA/F16C。
#   开 AVX 会在加载模型时 Illegal instruction（实测退出码 132）。
#   arm64 只需要关掉 native 嗅探，NEON 由 llama.cpp 自己处理。
#
# 模型：bge-small-zh-v1.5-f16（46MB），首次运行自动下载到 ~/.cache/openviking/models

FROM openviking/openviking:latest

ARG LLAMA_CPP_VERSION=0.3.36
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential cmake git \
 && if [ "$TARGETARCH" = "amd64" ]; then \
      export CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_AVX512=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_SSE42=ON -DCMAKE_C_FLAGS='-march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-bmi -mno-bmi2 -mno-fma -mno-f16c' -DCMAKE_CXX_FLAGS='-march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-bmi -mno-bmi2 -mno-fma -mno-f16c'"; \
    else \
      export CMAKE_ARGS="-DGGML_NATIVE=OFF"; \
    fi \
 && /usr/local/bin/pip wheel --no-deps --wheel-dir /tmp/wheels \
      "llama-cpp-python==${LLAMA_CPP_VERSION}" \
 && /usr/local/bin/pip install --no-deps \
      --target /app/.venv/lib/python3.13/site-packages \
      /tmp/wheels/llama_cpp_python-*.whl \
 && /usr/local/bin/pip install --no-deps --quiet \
      --target /app/.venv/lib/python3.13/site-packages \
      diskcache \
 && rm -rf /tmp/wheels \
 && if [ "$TARGETARCH" = "amd64" ]; then \
      echo "== 校验二进制里没有 AVX/AVX2/BMI2 指令 =="; \
      for f in /app/.venv/lib/python3.13/site-packages/llama_cpp/lib/*.so*; do \
        n=$(objdump -d "$f" | grep -cE "%ymm|%zmm|vzeroupper|shlx|shrx|sarx" || true); \
        echo "  $(basename $f) 违规指令=$n"; \
        [ "$n" -eq 0 ] || { echo "!! $f 含 AVX/BMI2 指令，会在老 CPU 上崩溃"; exit 1; }; \
      done; \
    fi \
 && apt-get purge -y build-essential cmake git \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/* /root/.cache/pip

# libgomp1 是 llama.cpp 的 OpenMP 运行时依赖，autoremove 会把它当成
# build-essential 的依赖一并删掉，导致 import 时 libgomp.so.1 not found
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# 构建期验证，失败就早点失败
RUN /app/.venv/bin/python -c "import llama_cpp, diskcache, platform; print('llama_cpp', llama_cpp.__version__, 'on', platform.machine())"

LABEL org.opencontainers.image.source="https://github.com/wxxxcxx/openviking-local-embed" \
      org.opencontainers.image.description="OpenViking with local llama-cpp embedding (bge-small-zh), SSE4.2 baseline for amd64 + arm64"
