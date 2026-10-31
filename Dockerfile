# OpenViking + 本地 GGUF embedding（llama-cpp-python）
#
# 官方镜像不含 llama-cpp-python，官方预编译轮子链接 musl，在这套 Debian 镜像上
# import 会失败。所以从源码编译，编完删工具链。
#
# 指令集：amd64 必须按 SSE4.2 基线编译。
#   Pentium Silver J5005（Gemini Lake）只有 SSE4.2 + POPCNT —— 没有 AVX、没有 BMI2。
#   开关和校验逻辑都在 scripts/build-llama.sh 里。
#   arm64 只需要关掉 native 嗅探，NEON 由 llama.cpp 自己处理。
#
# 模型：bge-small-zh-v1.5-f16（46MB），首次运行自动下载到 ~/.cache/openviking/models

FROM openviking/openviking:latest

ARG LLAMA_CPP_VERSION=0.3.36
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential cmake git \
 && rm -rf /var/lib/apt/lists/*

COPY scripts/build-llama.sh /tmp/build-llama.sh
RUN chmod +x /tmp/build-llama.sh && /tmp/build-llama.sh && rm -f /tmp/build-llama.sh

# libgomp1 是 llama.cpp 的 OpenMP 运行时依赖，autoremove 会把它当 build-essential
# 的依赖一起删掉，导致 import 时 libgomp.so.1 not found
RUN apt-get update \
 && apt-get purge -y build-essential cmake git \
 && apt-get autoremove -y \
 && apt-get install -y --no-install-recommends libgomp1 \
 && rm -rf /var/lib/apt/lists/* /root/.cache/pip

# 构建期验证，失败就早点失败
RUN /app/.venv/bin/python -c "import llama_cpp, diskcache, platform; print('llama_cpp', llama_cpp.__version__, 'on', platform.machine())"

LABEL org.opencontainers.image.source="https://github.com/wxxxcxx/openviking-local-embed" \
      org.opencontainers.image.description="OpenViking with local llama-cpp embedding (bge-small-zh), SSE4.2 baseline for amd64 + arm64"
