# openviking-local-embed-legacy

OpenViking 的镜像，**内含本地中文 embedding（llama-cpp + bge-small-zh）**，不需要额外跑
Ollama 容器。**专为只有 SSE4.2 的老 x86 CPU 构建**——比如飞牛 NAS 上那颗
Pentium Silver J5005（Gemini Lake）。

```
镜像    wxxxcxx/openviking-local-embed-legacy:latest
平台    linux/amd64（SSE4.2 基线）、linux/arm64（NEON）
tag     只有 latest，没有其他别名
```

## 为什么需要这个镜像

1. 官方镜像 `openviking/openviking` / `ghcr.io/volcengine/openviking` 都不含
   `llama-cpp-python`，没有它就跑不了本地 GGUF embedding；官方也没提供任何
   `cpu` / `full` / `local` 变体 tag。
2. 官方 CPU 轮子索引里 cp313 只有 `linux_x86_64`（musl 链接）的包，装进官方
   Debian 镜像直接失败：`OSError: libc.musl-x86_64.so.1: cannot open shared object file`。
   所以这个仓库在构建阶段从源码编译，编完把工具链删掉。
3. 编译出来的二进制默认带 AVX2 之类的指令，而 J5005 连 **AVX 都没有**，加载模型时
   直接 `Illegal instruction (core dumped)`。

## 指令集：这个镜像是怎么编的

N100/J5005 这一档 Gemini Lake 支持的扩展很少：

```
有    SSE、SSE2、SSSE3、SSE4.1、SSE4.2、POPCNT、AES、MOVBE、PCLMULQDQ
没有  AVX、AVX2、FMA、F16C、BMI2、AVX-512
```

所以 amd64 按 SSE4.2 基线编译：

```bash
# 编译器开关必须走 CFLAGS/CXXFLAGS：
# CMAKE_ARGS 里带空格的 -D 值会被 scikit-build 按空格拆开，静默失效
export CFLAGS="-O3 -march=x86-64 -mtune=generic -mno-avx -mno-avx2 \
-mno-avx512f -mno-bmi -mno-bmi2 -mno-fma -mno-f16c"
export CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_BMI2=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF \
-DGGML_AVX512=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_SSE42=ON"
```

**最容易踩的坑是 `GGML_BMI2`**：它是独立开关、默认 ON，上面那堆 AVX 开关都管不到它。
ggml-cpu 的 `CMakeLists.txt` 会据它加 `-mbmi2`，编出 `shlx` 指令，在没有 BMI2 的 CPU 上
一样崩。这个镜像里显式关掉了。

### 构建期断言

编完会反汇编每一个 `llama_cpp/lib/*.so*`，出现下面任一指令就直接让构建失败：

```bash
grep -cE '%ymm|%zmm|vzeroupper|shlx|shrx|sarx'
```

所以发布出来的镜像**保证**不含 AVX/AVX2/BMI2 指令，不会在 J5005 上崩。

## 用法

```bash
docker pull wxxxcxx/openviking-local-embed-legacy:latest
```

`ov.conf` 里写本地 embedding，模型首次运行会自动下载到
`~/.cache/openviking/models/`（46MB）：

```json
"embedding": {
  "dense": { "provider": "local", "model": "bge-small-zh-v1.5-f16" },
  "max_concurrent": 2
}
```

**`max_concurrent` 不要超过 2**：社区 issue #5528 报告过，默认高并发下本地 GGUF
embedder 会段错误。

## 实测（J5005，4 核 1.5GHz，内存 7.8G）

```
容器常驻      ~540MB
单条 embedding  ~0.27s（512 维）
20 条记忆召回  平均 1.55s
记忆抽取       20 条 / 65s（走云端 VLM，与 NAS CPU 无关）
中文召回       20 条语料 + 10 个换说法问法 → 10/10 top-3 命中
```

## 已知限制

- 只适合老 CPU。现代 x86 上比 AVX2 版本慢，想要快就自己改 CFLAGS 编一版。
- 本地 embedding 只支持 `bge-small-zh-v1.5-f16` 一个模型名，换 bge-m3 要走 Ollama/TEI。
- 镜像基于 `openviking/openviking:latest`，上游更新后需要重新跑一次 workflow。

## Secrets

| 名称 | 用途 |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub access token（Read & Write） |
