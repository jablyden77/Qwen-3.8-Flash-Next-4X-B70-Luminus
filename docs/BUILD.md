# Reproducible build record

## 1. Hardware and prerequisites

The deployed host was a Threadripper PRO 5955WX (16C/32T), four Intel Arc Pro B70 32 GiB GPUs, 128 GB nominal DDR4 RAM (123 GiB usable), Ubuntu kernel 7.0.0-38-generic, and a dedicated ~1.8 TB NVMe volume at /models. The WRX80E-SAGE SE board came from the design specification, not an independent DMI measurement. Confirm GPU PCIe link widths and compute runtime version yourself.

Do **not** assume the published Lumnus 256 GB reference host has the same memory capacity as a 128 GB deployment.

## 2. Verify upstream code and kernel wheel

```bash
git clone https://github.com/Lumnus/b70-flash-next.git
cd b70-flash-next
git checkout v0.30.0-b70.2
test "$(git rev-parse HEAD)" = b103e0f4522316b6368e135586b69a8bd3d37cf0
bash scripts/check-series.sh
bash scripts/make-tree.sh 0.30.0-b70.2 /path/to/vllm-b70
```

The patch-series check passed, and the assembled vLLM source passed **33/33 final file-hash checks**.

Download the `0.1.14.1+b70.3` wheel from the [pinned Lumnus release](https://github.com/Lumnus/b70-flash-next/releases/tag/v0.30.0-b70.2). Check its SHA-256:

```
f104a3e5f61480681284ec3632e1a6692358b72a1fbdbda7406db0d7b7d1d589
```

Recorded wheel: `vllm_xpu_kernels-0.1.14.1+b70.3-cp38-abi3-manylinux_2_28_x86_64.whl`.

## 3. Obtain AWQ and build the serving snapshot

Pinned repo: `wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16`, revision `0939125`. The raw source index reported **180,725,866,024 bytes** because its first shard contains the original BF16 PLE tensors. Its compressed model-serving tensor inventory is smaller than the raw on-disk checkpoint; do not conflate these sizes.

```bash
hf download wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16 --revision 0939125 --local-dir /models/Lumnus-AWQ-source
python3 tools/awq_snapshot.py snapshot \
  /models/Lumnus-AWQ-source \
  /models/Qwen3.8-Flash-Next-W4A16/ple_table_qwen4exp.pt \
  /models/Lumnus-AWQ-snapshot
python3 tools/awq_snapshot.py serve-config \
  image/files/opt/b70-flashnext/serve-config.json /path/to/awq-serve-config.json
cp /path/to/awq-serve-config.json /models/Lumnus-AWQ-snapshot/config.json
```

Observed snapshot: **222,746 → 222,579** tensor references; 128 embedded PLE tensors and 39 unused indexer tensors filtered. Configuration SHA-256:

```
c7a2b345927976d911cfd57d1083b71d1a75fee245f61a17b8f126b6717342c8
```

The snapshot symlinks weights; filtering manifest references does **not** shrink the source shard on disk.

## 4. Build and verify INT8 PLE

The original BF16 table was about 95.4 GiB. Lumnus conversion generated a 52,480,256,280-byte (~48.9 GiB) INT8 rowscale table in about 352 s.

```bash
BF16_PT=/models/Qwen3.8-Flash-Next-W4A16/ple_table_qwen4exp.pt \
OUT_DIR=/models/Lumnus-INT8-PLE \
python3 tools/build_int8_ple.py build
BF16_PT=/models/Qwen3.8-Flash-Next-W4A16/ple_table_qwen4exp.pt \
OUT_DIR=/models/Lumnus-INT8-PLE \
python3 tools/build_int8_ple.py verify
```

Recorded resulting SHA-256:

```
038b8458a5c581be1cf5e761e90f69e0c825962e3e3fa41bafcf65ba0f334af0
```

All four ranks passed the INT8 PLE relative L2 cross-check (~0.0066 versus limit 0.02) and NVMe native reader/device-hash checks.

## 5. Why the upstream Dockerfile wasn't used unchanged

The pinned `ghcr.io/wu1ff/qwen38-flashnext-b70:1.0.0` image/digest in the upstream build returned `not found`. **Do not substitute a random digest.**

The observed workaround was to create a thin local image (see `deploy/Dockerfile.fallback`) from:

- `vllm/vllm-openai-xpu@sha256:fc0e112afb64e3a06fe8daff34652435822a629412f38efce8f0f67a46636b8d`
- verified Lumnus patched source `vllm-b70`
- verified `0.1.14.1+b70.3` XPU kernel wheel

The patched source was exposed via `PYTHONPATH=/srv/vllm-b70`. Since wu1ff's closed peer-residency shim was unavailable, `LD_PRELOAD` was unset. The engine used `B70_GDN_MODE=official` with the newer kernels.

This fallback **does not claim bit-for-bit equivalence** with Lumnus's published image, and requires independent testing.

## 6. Successful boot settings

See `deploy/start.example.sh` for a template. The successful boot used:

- `--tensor-parallel-size 4`, `--enable-expert-parallel`
- MTP speculative `num_speculative_tokens=3`
- `--max-model-len 262144`, `--max-num-seqs 16`
- `--gpu-memory-utilization 0.88`
- `--max-num-batched-tokens 1024`
- INT8 PLE from NVMe, 8 GiB pinned cache
- **no** `--kv-offloading-size` argument

The deployment first failed OOM with the RAM-resident PLE; then failed OOM when allocating a 32 GiB host KV tier. The final successful boot kept NVMe PLE but disabled the host KV tier. The kernel confirmed a global OOM and a vLLM worker kill during the failed offload attempt.

API /health returned HTTP 200 and a real chat completion returned `Lumnus is operational.` after about 1.5 seconds.

## 7. Reproduction and security notes

Use your own volumes and bindings. This public repository intentionally omits IP addresses, authentication material, private key files, HF tokens, raw weight shards, the INT8 PLE binary, runtime caches, and host-specific logs. Do not publish model artifacts without confirming upstream licensing and distribution terms.

The locally benchmarked model was operational but **not production-soak certified**. Memory remained pressured (roughly 18 GiB swap in use at last check), and long-context stress tests were pending.
