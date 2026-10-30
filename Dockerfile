# OpenViking + 本地 GGUF embedding（llama-cpp-python）
#
# 为什么需要这个镜像：官方镜像不含 llama-cpp-python，而官方预编译轮子在这套
# Debian 基础镜像上 import 会失败（libc.musl-x86_64.so.1 not found）。
# 所以构建阶段从源码编译，编完把工具链删掉。
#
# 编译参数按架构分流：
#   amd64  GGML_NATIVE=OFF，只开 AVX，关 AVX2/FMA/F16C
#          → Gemini Lake（J5005）和老 Xeon 都能跑；开 native 会 illegal instruction
#   arm64  只关 native，NEON 由 llama.cpp 自己处理
#
# 模型：bge-small-zh-v1.5-f16（46MB），首次运行自动下载到 ~/.cache/openviking/models

FROM openviking/openviking:latest

ARG LLAMA_CPP_VERSION=0.3.36
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential cmake git \
 && if [ "$TARGETARCH" = "amd64" ]; then \
      export CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF"; \
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
 && apt-get purge -y build-essential cmake git \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/* /root/.cache/pip

# libgomp1 是 llama.cpp 的 OpenMP 运行时依赖，apt autoremove 会把它当成
# build-essential 的依赖一并删掉，导致 import 时 libgomp.so.1 not found
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgomp1 \
 && rm -rf /var/lib/apt/lists/*


# 构建期验证，失败就早点失败
RUN /app/.venv/bin/python -c "import llama_cpp, diskcache, platform; print('llama_cpp', llama_cpp.__version__, 'on', platform.machine())"

LABEL org.opencontainers.image.source="https://github.com/wxxxcxx/openviking-local-embed" \
      org.opencontainers.image.description="OpenViking with local llama-cpp embedding (bge-small-zh), portable multi-arch build"
