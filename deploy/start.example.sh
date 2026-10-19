#!/usr/bin/env bash
# Example of the *successful benchmark profile*, with private machine details removed.
# Run only after reading docs/BUILD.md. This is NOT the upstream Lumnus pack launcher.
set -euo pipefail

: "${LUMNUS_DIR:?Set LUMNUS_DIR to cloned Lumnus release directory}"
: "${MODELS_DIR:?Set MODELS_DIR to the host's model volume}"

ENGINE_ARGS="${LUMNUS_DIR}/engines/serve-s16-mtp3.args"
mkdir -p "${MODELS_DIR}/Lumnus-cache/tmp"

# Each upstream args-file line is either --flag or "--flag value".
# Preserve JSON arguments as one value; do not whitespace-split all words.
ARGS=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  if [[ "$line" == *" "* ]]; then
    ARGS+=("${line%% *}" "${line#* }")
  else
    ARGS+=("$line")
  fi
done < "$ENGINE_ARGS"

# No host KV offload in the benchmarked, successful deployment.
# Do not add --kv-offloading-size without retesting host memory.
docker run -d \
  --name lumnus-flash-next \
  --privileged --network host --ipc host --shm-size 16g --device /dev/dri \
  --restart unless-stopped \
  --env-file "${LUMNUS_DIR}/engines/common.env" \
  --env-file "${LUMNUS_DIR}/engines/s16-kv128-mtp3.env" \
  -e LD_PRELOAD= \
  -e B70_GDN_MODE=official \
  -e B70_PLE_INT8_NVME=1 \
  -e B70_PLE_INT8_PATH=/models/Lumnus-INT8-PLE/ple_ngram_int8_rowscale.safetensors \
  -e B70_PLE_INT8_NVME_PATH=/models/Lumnus-INT8-PLE/ple_ngram_int8_rowscale.safetensors \
  -e PLE_TABLE_PATH=/models/Qwen3.8-Flash-Next-W4A16/ple_table_qwen4exp.pt \
  -e HF_HOME=/cache/hf \
  -e TMPDIR=/cache/tmp \
  -e VLLM_CACHE_ROOT=/cache/vllm \
  -v "${MODELS_DIR}:/models" \
  -v "${MODELS_DIR}/Lumnus-cache:/cache" \
  b70-flash-next:lumnus-fallback \
  --model /models/Lumnus-AWQ-snapshot "${ARGS[@]}"

# Check: curl -fsS http://127.0.0.1:8000/health
