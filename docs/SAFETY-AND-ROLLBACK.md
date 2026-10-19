# Safety, caveats and rollback

This is a public reproduction repository. Never check in local credentials, private interfaces, host inventory secrets, access tokens, logs containing request payloads, or model/PLE binaries.

## Observed failures

1. Published Lumnus Dockerfile required pinned ghcr.io/wu1ff pack image; registry returned `not found`. No arbitrary alternate digest was trusted.
2. RAM-resident INT8 PLE load on 128 GB nominal host memory: process exited 137 under memory pressure.
3. NVMe PLE plus 32 GiB host KV offload: kernel log recorded a global OOM and killed a vLLM worker.
4. NVMe INT8 PLE with 8 GiB pinned row cache and host KV offload disabled: **successful** inference and benchmarks.

The 262K max context and 16 max sequences are **configured**, not proven sustainable at full lengths under constrained host RAM. Distinguish short benchmark success from soak certification.

## Verification

```bash
docker ps --filter name=lumnus-flash-next
curl -fsS http://127.0.0.1:8000/health
curl -s http://127.0.0.1:8000/v1/models
free -h
docker logs --tail 80 lumnus-flash-next
```

## Rollback

Keep older model images, weights and configs untouched. Stop this deployment using `docker stop lumnus-flash-next`; disable its auto-restart before switching services. Only restart an existing prior deployment using its own validated launch configuration and ports. Rollbacks are operational actions, not implied by this README.

## Outstanding acceptance gates

- 5+ repeated runs and variance for decode and prefill.
- Internal prefill compute vs client-observed TTFT.
- Long-context 64K, 128K, 262K functional tests.
- MTP3 draft acceptance and paired correctness against MTP off.
- 30 C=10 repeated bursts (no NaN, no aborted requests).
- 24-hour stability soak with swap growth, memory and GPU/GT reset monitoring.
- Confirm real PCIe link widths, compute runtime, GPU clocks and utilization.
