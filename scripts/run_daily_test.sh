#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Orchestrate all PyPI vs GitHub comparison tests.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/scripts/common.sh"

export WORK_DIR="${WORK_DIR:-${ROOT_DIR}/.work}"
export RESULT_DIR="${RESULT_DIR:-${ROOT_DIR}/results/$(date +%Y%m%d_%H%M%S)}"
export PYTHON_BIN="${PYTHON_BIN:-python3}"
export KEEP_WORK="${KEEP_WORK:-0}"

mkdir -p "${WORK_DIR}" "${RESULT_DIR}"
log "Result directory: ${RESULT_DIR}"

FAILED=0

log "===== [1/2] fosslight_scanner test ====="
set +e
"${ROOT_DIR}/scripts/run_scanner_test.sh"
SCANNER_RC=$?
set -e
if [[ "${SCANNER_RC}" -ne 0 ]]; then
  log "fosslight_scanner test failed (exit ${SCANNER_RC})"
  FAILED=1
fi

log "===== [2/2] fosslight_yocto test ====="
set +e
"${ROOT_DIR}/scripts/run_yocto_test.sh"
YOCTO_RC=$?
set -e
if [[ "${YOCTO_RC}" -ne 0 ]]; then
  log "fosslight_yocto test failed (exit ${YOCTO_RC})"
  FAILED=1
fi

if [[ "${KEEP_WORK}" != "1" ]]; then
  rm -rf "${WORK_DIR}"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Overall summary"
    echo ""
    echo "| Test | Result |"
    echo "|------|--------|"
    if [[ "${SCANNER_RC}" -eq 0 ]]; then
      echo "| fosslight_scanner | ✅ Success |"
    else
      echo "| fosslight_scanner | ❌ Failure |"
    fi
    if [[ "${YOCTO_RC}" -eq 0 ]]; then
      echo "| fosslight_yocto | ✅ Success |"
    else
      echo "| fosslight_yocto | ❌ Failure |"
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
fi

if [[ "${FAILED}" -ne 0 ]]; then
  log "FAILURE: one or more comparison tests found differences."
  exit 1
fi

log "SUCCESS: all comparison tests passed (no Excel differences)."
exit 0
