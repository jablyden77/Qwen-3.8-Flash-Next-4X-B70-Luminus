# Measured benchmark record — October 18–19, 2026

**Host:** 4× Arc Pro B70, TP4 + EP; Qwen3.8-Flash-Next AWQ W4A16; Lumnus v0.30.0-b70.2 patched vLLM; b70.3 XPU kernels; MTP k=3; NVMe INT8 PLE, 8 GiB row cache; no host KV offload.

**Method:** Python `requests`, monotonic clock, OpenAI-compatible `/v1/chat/completions` API. All measured values are from the running host (not published performance projections). Output token counts from `usage.completion_tokens`. Streaming TTFT is first nonempty reasoning/content delta; decode = `(completion_tokens - 1)/(stream_end - first_token_time)`. Aggregate = all output tokens divided by batch wall time.

## Single-stream decoding

| Workload | Completion tokens | TTFT | Wall time | Decode tok/s | End-to-end tok/s |
|---|---:|---:|---:|---:|---:|
| 256 generated | 256 | 0.277 s | 3.220 s | 86.67 | 79.51 |
| 512 generated | 512 | 0.139 s | 5.801 s | **90.25** | 88.26 |
| Prior Devan-based deployment, 512 generated | 512 | 0.133 s | 9.442 s | 54.89 | 54.22 |

The Lumnus 512-token decode speed was ~64.4% faster than the prior deployment's 54.89 tok/s. Not a strict A/B quality or prompt equivalence test.

## Concurrent decoding — 512 completion tokens/request

| Concurrent streams | Total generated | Batch wall | Aggregate tok/s | Mean share/stream |
|---|---:|---:|---:|---:|
| 1 | 512 | 5.801 s | 88.26 | 88.26 |
| 2 | 1,024 | 6.380 s | **160.59** | 80.30 |
| 4 | 2,048 | 7.540 s | **271.78** | 67.95 |
| 8 | 4,096 | 10.040 s | **407.92** | 50.99 |
| 10 | 5,120 | 10.650 s | **480.75** | 48.08 |

All 24 concurrent requests at C=2/4/8/10 returned HTTP 200 and 512 generated tokens; all ended at the length limit. The single C=1 run was separately measured.

## Single-prompt prefill, one output token

| Prompt tokens | Cached tokens | TTFT / total wall | Effective prompt tokens/s |
|---|---:|---:|---:|
| 1,602 | 0 | 0.415 s | 3,859.5 |
| 6,222 | 0 | 1.426 s | **4,362.3** |
| 24,562 | 4,992 | 4.623 s | 5,312.7 (**cache-aided**) |

These are client-observed effective rates including tokenization, API scheduling, and first output overhead. The last row is **not** an uncached compute prefill result.

## Concurrent prefill — unique pseudo-randomized prompts; 1 output token/request

| Concurrent streams | Total input tokens | Cached tokens | Batch wall | Effective aggregate input tok/s | Median TTFT | Maximum TTFT |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 6,946 | 0 | 2.340 s | 2,967.9 | 2.338 s | 2.338 s |
| 2 | 13,809 | 0 | 3.503 s | **3,942.3** | 2.655 s | 3.500 s |
| 4 | 27,594 | 0 | 6.418 s | **4,299.7** | 4.074 s | 6.412 s |
| 8 | 55,339 | 0 | 12.403 s | **4,461.6** | 7.035 s | 12.392 s |
| 10 | 69,077 | 0 | 15.314 s | **4,510.8** | 8.456 s | 15.299 s |

Each request used a distinct pseudo-randomized technical-word sequence. All 25 requests returned HTTP 200 and reported zero cached prompt tokens. TTFTs are staggered, consistent with chunked/near-serial scheduling, but no low-level scheduler trace was captured.

## Post-benchmark checks

- `/health`: HTTP 200
- Container: running with `unless-stopped` restart policy
- Sampled recent logs: no traceback, DEVICE_LOST, NaN-detected or aborted-request messages
- Host: approximately 123 GiB used, 18 GiB swap in use, a few hundred MiB MemAvailable at final inspection

**Limits:** one representative run per workload, no confidence intervals or long-context verification. Tests did not include 16-stream capacity, 24-hour soak, MTP draft acceptance measurement, energy/power, or standardized prefill/decode workloads. No production-stability guarantee is implied.
