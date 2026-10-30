# OpenViking 中文镜像（含本地 embedding）
#
# 官方镜像不含 llama-cpp-python，而官方提供的预编译轮子是 musl 链接的，
# 装进这个 Debian 基础镜像会 import 失败（libc.musl-x86_64.so.1 not found）。
# 所以在构建阶段从源码编译，再把编译工具链删掉。
#
# 关键编译参数：GGML_NATIVE=OFF
#   否则在 GitHub runner（支持 AVX2/AVX512）上编出的二进制，
#   拿到 J5005（只支持 SSE4.2 + AVX）会直接 illegal instruction。
#   这里按 Gemini Lake 能用的指令集编：AVX 开，AVX2/FMA/F16C 关。

FROM openviking/openviking:latest

ARG LLAMA_CPP_VERSION=0.3.36

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential cmake git \
 && CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF" \
    /usr/local/bin/pip wheel --no-deps --wheel-dir /tmp/wheels \
      "llama-cpp-python==${LLAMA_CPP_VERSION}" \
 && /usr/local/bin/pip install --no-deps \
      --target /app/.venv/lib/python3.13/site-packages \
      /tmp/wheels/llama_cpp_python-*.whl \
 && /usr/local/bin/pip install --no-deps \
      --target /app/.venv/lib/python3.13/site-packages \
      diskcache \
 && rm -rf /tmp/wheels \
 && apt-get purge -y --auto-remove build-essential cmake git \
 && rm -rf /var/lib/apt/lists/* /root/.cache/pip

# 构建期就验证，别等部署时才发现
RUN /app/.venv/bin/python -c "import llama_cpp, diskcache; print('llama_cpp', llama_cpp.__version__)"

LABEL org.opencontainers.image.source="https://github.com/wxxxcxx/openviking-local-embed" \
      org.opencontainers.image.description="OpenViking + llama-cpp local embedding (bge-small-zh), portable x86-64 build"
