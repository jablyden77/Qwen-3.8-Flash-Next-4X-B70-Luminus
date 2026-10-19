# Qwen3.8-Flash-Next on 4× Intel Arc Pro B70 — Lumnus AWQ Build

**Reproduced deployment and measurements, October 18–19, 2026.**

This repository records a working **Qwen3.8-Flash-Next AWQ W4A16** inference deployment with four Intel Arc Pro B70 GPUs, using the [Lumnus/b70-flash-next](https://github.com/Lumnus/b70-flash-next) **v0.30.0-b70.2** patched vLLM code and **b70.3** XPU kernels. The server successfully returned OpenAI-compatible chat completions. **It is a local source-based fallback, not a byte-identical reproduction of the upstream Lumnus Docker container.**

## Results: measured on BRUTICUS

| Metric | Measured |
|---|---:|
| Single stream decode, 512 tokens, excluding TTFT | **90.25 tok/s** |
| Single stream TTFT, 512-token sample | **139 ms** |
| Aggregate decode, C=2 | **160.59 tok/s** |
| Aggregate decode, C=4 | **271.78 tok/s** |
| Aggregate decode, C=8 | **407.92 tok/s** |
| Aggregate decode, C=10 | **480.75 tok/s** |
| Uncached single-request effective prefill, 6,222 tokens | **4,362.3 input tok/s** |
| Uncached aggregate effective prefill, C=10 | **4,510.8 input tok/s** |

**Measurement distinction:** decode numbers use API-reported completion tokens and client monotonic timing; concurrent decode is total completion tokens divided by batch wall time. Prefill numbers are *effective client-observed input tokens/TTFT or batch wall*, not isolated GPU prefill kernel timings. The 24,562-token single-prompt result of 5,312.7 tok/s had 4,992 cached tokens and is **not** an uncached figure.

## Hardware

- CPU: AMD Threadripper PRO 5955WX, 16 cores / 32 logical CPUs.
- GPUs: 4 × Intel Arc Pro B70, 32 GB each; 128 GB aggregate VRAM.
- Host memory: 128 GB nominal (Linux reports 123 GiB).
- Model drive: dedicated NVMe at `/models`, approximately 1.8 TB formatted.
- Host kernel measured: `7.0.0-38-generic`.
- Motherboard: ASUS WRX80E-SAGE SE from build specification (not independently reverified in final inspection).

## Recipe and upstream credit

**Credit goes to [Lumnus/b70-flash-next](https://github.com/Lumnus/b70-flash-next)** and its referenced upstream contributors (including wu1ff), not this repository. The Lumnus release contains the actual patch series and serving recipe. This repository is a reproduction record and local deployment wrapper, **not a fork or redistribution of their patched source**.

| Item | Pinned identity |
|---|---|
| Lumnus tag | `v0.30.0-b70.2` |
| Source commit | `b103e0f4522316b6368e135586b69a8bd3d37cf0` |
| Base image digest | `sha256:fc0e112afb64e3a06fe8daff34652435822a629412f38efce8f0f67a46636b8d` |
| XPU kernel wheel | `vllm_xpu_kernels-0.1.14.1+b70.3` |
| Wheel SHA-256 | `f104a3e5f61480681284ec3632e1a6692358b72a1fbdbda7406db0d7b7d1d589` |
| AWQ weights | `wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16`, rev `0939125` |
| BF16 PLE source | Existing `ple_table_qwen4exp.pt` from compatible Flash-Next checkpoint |

The original release Dockerfile expected `ghcr.io/wu1ff/qwen38-flashnext-b70:1.0.0` at a pinned digest. At deployment time that artifact returned **not found**. The fallback used the pinned official vLLM XPU base, installed the verified b70.3 kernel wheel and supplied the verified patched Lumnus vLLM tree via `PYTHONPATH`. This omits the unavailable private peer-residency shim and uses `B70_GDN_MODE=official`.

## Actually deployed configuration

- AWQ W4A16, TP=4 + expert parallelism.
- MTP speculative decoding **k=3**; **not MTP4**.
- `max_model_len=262144` and `max_num_seqs=16` *configured*, not long-context/16-stream stress verified.
- `gpu_memory_utilization=0.88`; `max_num_batched_tokens=1024`.
- INT8 PLE table (~48.9 GiB) **served from NVMe**, with 8 GiB aggregate pinned row cache.
- **Host KV offloading disabled** on the successful boot. Both RAM-resident PLE and 32 GiB host KV offload triggered OOM failures.
- Local image `b70-flash-next:lumnus-fallback`, serving model ID `qwen38-flash-next`.
- API follows OpenAI-compatible `/v1/chat/completions` conventions, port 8000 in the example.

## Reproduce

See [docs/BUILD.md](docs/BUILD.md) for step-by-step assembly, [deploy/](deploy/) for the Dockerfile and launcher template, and [docs/BENCHMARKS.md](docs/BENCHMARKS.md) for methodology and all benchmark tables. **Do not commit model weights, the 49 GiB PLE table, cache, secrets, or private host configuration to this repository.**

## Production caveat

The measured runtime passed short generation and concurrent prefill/decode tests and remained healthy afterward, but host memory was near exhaustion with approximately 18 GiB swap used. The 24-hour soak, MTP acceptance profiling, 30× burst repetition, 64K/128K/262K functional stress and PCIe verification **have not been completed**. Do not represent this as production-certified.

## License and attribution

Upstream model, third-party code, and binaries retain their respective licenses. Review [Lumnus provenance](https://github.com/Lumnus/b70-flash-next/blob/v0.30.0-b70.2/PROVENANCE.md) and model repository terms before redistributing artifacts.
