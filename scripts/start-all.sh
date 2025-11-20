#!/usr/bin/env bash

# 一键启动嵌入服务 + Action Server + 主服务（assistant）
# 说明：
# - 默认使用 addons/embed_service.py 提供的本地嵌入服务，端口 10010。
# - Action Server 日志输出到 /tmp/rasa_actions.log，嵌入服务日志输出到 /tmp/embed_service.log。
# - 主服务在前台输出日志，便于观察；Ctrl+C 退出时会自动清理后台进程。

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source /opt/anaconda3/etc/profile.d/conda.sh
conda activate rasa-ecs

set -a
source "${PROJECT_ROOT}/.env"
set +a

cd "${PROJECT_ROOT}"

LOG_DIR="${LOG_DIR:-/tmp}"
mkdir -p "${LOG_DIR}"

EMBED_HOST="${EMBED_HOST:-0.0.0.0}"
EMBED_PORT="${EMBED_PORT:-10010}"
# 如果未显式设置 EMBED_MODEL_PATH，但本地 models 目录下存在默认模型，则自动使用
if [[ -z "${EMBED_MODEL_PATH:-}" && -d "${PROJECT_ROOT}/models/bge-base-zh-v1.5" ]]; then
  export EMBED_MODEL_PATH="${PROJECT_ROOT}/models/bge-base-zh-v1.5"
  echo "[INFO] 检测到本地嵌入模型，自动使用 EMBED_MODEL_PATH=${EMBED_MODEL_PATH}"
fi

check_port() {
  python - "$1" "$2" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket()
s.settimeout(0.5)
try:
    s.connect((host, port))
except OSError:
    sys.exit(1)
else:
    sys.exit(0)
finally:
    s.close()
PY
}

EMBED_PID=""
if check_port "${EMBED_HOST}" "${EMBED_PORT}"; then
  echo "[INFO] 嵌入服务已在 ${EMBED_HOST}:${EMBED_PORT} 监听，跳过启动。"
else
  echo "[INFO] 启动嵌入服务: ${EMBED_HOST}:${EMBED_PORT} ..."
  nohup python addons/embed_service.py --host "${EMBED_HOST}" --port "${EMBED_PORT}" \
    > "${LOG_DIR}/embed_service.log" 2>&1 &
  EMBED_PID=$!
  echo "[INFO] 嵌入服务 PID=${EMBED_PID} 日志: ${LOG_DIR}/embed_service.log"
fi

echo "[INFO] 启动 Action Server (日志: ${LOG_DIR}/rasa_actions.log)..."
nohup rasa run actions --debug \
  > "${LOG_DIR}/rasa_actions.log" 2>&1 &
ACTIONS_PID=$!
echo "[INFO] Action Server PID=${ACTIONS_PID}"

cleanup() {
  echo "[INFO] 停止后台进程..."
  kill ${ACTIONS_PID:-} ${EMBED_PID:-} 2>/dev/null || true
}
trap cleanup EXIT

echo "[INFO] 启动主服务 (assistant)..."
bash "${PROJECT_ROOT}/scripts/start-assistant.sh" "$@"
