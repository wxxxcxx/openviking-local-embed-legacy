# openviking-local-embed

OpenViking 的 x86-64 镜像，**带上本地中文 embedding（llama-cpp + bge-small-zh）**，
不需要额外跑 Ollama 容器。

## 为什么需要这个镜像

官方镜像 `openviking/openviking` / `ghcr.io/volcengine/openviking` 都不含
`llama-cpp-python`，而没有它就跑不了本地 GGUF embedding；官方也没有提供任何
`cpu` / `full` / `local` 变体 tag。

官方 CPU 轮子索引里 cp313 只有 `linux_x86_64`（musl 链接）的包，装进官方
Debian 镜像会直接失败：

```
OSError: libc.musl-x86_64.so.1: cannot open shared object file
```

所以这个仓库在构建阶段从源码编译，编译完把工具链删掉。

## 用法

```bash
docker pull 你的用户名/openviking-local-embed:latest
```

`ov.conf` 里只要写本地 embedding，模型首次运行会自动下载到
`~/.cache/openviking/models/`（46MB）：

```json
"embedding": {
  "dense": { "provider": "local", "model": "bge-small-zh-v1.5-f16" },
  "max_concurrent": 2
}
```

**`max_concurrent` 不要超过 2**：社区 issue #5528 报告过，默认高并发下
本地 GGUF embedder 会段错误。

## 构建参数说明

```dockerfile
CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF"
```

不这么写的话，GitHub runner（有 AVX2/AVX512）编出的二进制拿到老 CPU
（比如 Pentium Silver J5005）上会 `illegal instruction`。
这里按 Gemini Lake 支持的指令集编：开 AVX，关 AVX2/FMA/F16C。

如果你确定只在新 CPU 上跑，可以改成 `-DGGML_NATIVE=ON` 换取更快速度，
但那个镜像就不通用了。

## 已知限制

- 只构建 `linux/amd64`。ARM 上官方镜像本身就没有 cp313 aarch64 轮子，
  源码编译也会因为缺依赖链更麻烦。
- 本地 embedding 只支持 `bge-small-zh-v1.5-f16` 一个模型名，
  代码里的模型注册表写死了一个条目，换 bge-m3 必须走 Ollama/TEI。
- 镜像基于 `openviking/openviking:latest`，上游更新后需要重新跑一次 workflow。

## Secrets

| 名称 | 用途 |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub access token（Read & Write） |
