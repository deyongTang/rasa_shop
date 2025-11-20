#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source /opt/anaconda3/etc/profile.d/conda.sh
conda activate rasa-ecs

# 加载 .env 变量
set -a
source "${PROJECT_ROOT}/.env"
set +a

cd "${PROJECT_ROOT}"
USE_DEFAULT_MODEL=true
for arg in "$@"; do
  if [[ "$arg" == "--model" || "$arg" == "-m" ]]; then
    USE_DEFAULT_MODEL=false
    break
  fi
done

MODEL_ARGS=()
if $USE_DEFAULT_MODEL; then
  LATEST_MODEL=$(ls -t "${PROJECT_ROOT}"/models/*.tar.gz 2>/dev/null | head -n 1 || true)
  if [[ -z "${LATEST_MODEL}" ]]; then
    echo "[ERROR] models/ 目录下未找到 tar.gz 模型，请先执行 'rasa train' 或手动使用 --model 指定路径。" >&2
    exit 1
  fi
  echo "[INFO] 未显式指定模型，默认加载: ${LATEST_MODEL}"
  MODEL_ARGS=(--model "${LATEST_MODEL}")
fi

rasa run "${MODEL_ARGS[@]}" \
  --endpoints endpoints.yml \
  --credentials credentials.yml \
  --cors "*" --debug "$@"
