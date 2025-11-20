#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source /opt/anaconda3/etc/profile.d/conda.sh
conda activate rasa-ecs

set -a
source "${PROJECT_ROOT}/.env"
set +a

cd "${PROJECT_ROOT}"
rasa run actions --debug "$@"
