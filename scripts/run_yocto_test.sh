#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Compare fosslight_yocto Excel: pip install fosslight_yocto vs GitHub install.
#
# Uses test input files from:
#   https://github.com/fosslight/fosslight_yocto_scanner/tree/main/test_files
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/scripts/common.sh"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/.work}"
BASE_RESULT_DIR="${RESULT_DIR:-${ROOT_DIR}/results/$(date +%Y%m%d_%H%M%S)}"
RESULT_DIR="${BASE_RESULT_DIR}/yocto"
PYTHON_BIN="${PYTHON_BIN:-python3}"
KEEP_WORK="${KEEP_WORK:-0}"
# Canonical fixture path (same relative paths as the documented command)
TEST_FILES_DIR="${TEST_FILES_DIR:-${ROOT_DIR}/test_files}"

PYPI_VENV="${WORK_DIR}/venv_yocto_pypi"
GIT_VENV="${WORK_DIR}/venv_yocto_git"
PYPI_OUT="${RESULT_DIR}/pypi"
GIT_OUT="${RESULT_DIR}/github"

# Exact command requested by the test (paths relative to ROOT_DIR)
YOCTO_CMD_ARGS=(
  -ip test_files/installed-packages.txt
  -i test_files/installed-package-names.txt
  -b test_files/bom.json
  -p test_files/packages
  -y test_files/oss-pkg-info.yaml
)

run_yocto() {
  local out_dir="$1"
  local run_label="$2"
  mkdir -p "${out_dir}"

  local run_out="${ROOT_DIR}/test_result_${run_label}"
  rm -rf "${run_out}"

  (
    cd "${ROOT_DIR}"
    log "Running from ${ROOT_DIR}:"
    log "  fosslight_yocto ${YOCTO_CMD_ARGS[*]} -o ${run_out}"
    fosslight_yocto "${YOCTO_CMD_ARGS[@]}" -o "${run_out}"
  )

  local excel
  excel="$(find_excel "${run_out}" 'fosslight_report_yocto_*.xlsx')"
  mkdir -p "${out_dir}"
  cp -f "${excel}" "${out_dir}/"
  cp -f "${excel}" "${out_dir}/fosslight_report_yocto.xlsx"
  log "Yocto excel (${run_label}): ${excel}"

  if [[ "${KEEP_WORK}" != "1" ]]; then
    rm -rf "${run_out}"
  fi
}

mkdir -p "${WORK_DIR}" "${RESULT_DIR}"
log "Yocto result directory: ${RESULT_DIR}"

# Ensure fixtures from fosslight_yocto_scanner/test_files are present
fetch_yocto_test_files "${TEST_FILES_DIR}" "${WORK_DIR}"

# --- PyPI baseline ---
log "Creating PyPI virtualenv for fosslight_yocto"
create_venv "${PYPI_VENV}" "${PYTHON_BIN}"
# shellcheck disable=SC1090
source "${PYPI_VENV}/bin/activate"
log "Installing fosslight_yocto from PyPI"
python -m pip install fosslight_yocto
print_package_versions "yocto-PyPI" fosslight_yocto fosslight_util fosslight_source fosslight_binary
run_yocto "${PYPI_OUT}" "pypi"
cp -f "${PYPI_OUT}/fosslight_report_yocto.xlsx" "${RESULT_DIR}/fosslight_report_yocto_pypi.xlsx"
deactivate

# --- GitHub packages ---
log "Creating GitHub virtualenv for fosslight_yocto"
create_venv "${GIT_VENV}" "${PYTHON_BIN}"
# shellcheck disable=SC1090
source "${GIT_VENV}/bin/activate"
log "Installing FOSSLight packages from GitHub (same set as scanner test)"
python -m pip install "${GIT_PACKAGES[@]}"
print_package_versions "yocto-GitHub" \
  fosslight_yocto fosslight_util fosslight_source fosslight_binary \
  fosslight_dependency fosslight_scanner fosslight_android
run_yocto "${GIT_OUT}" "github"
cp -f "${GIT_OUT}/fosslight_report_yocto.xlsx" "${RESULT_DIR}/fosslight_report_yocto_github.xlsx"
deactivate

# --- Compare (openpyxl via git venv) ---
# shellcheck disable=SC1090
source "${GIT_VENV}/bin/activate"
set +e
compare_excels \
  "${ROOT_DIR}" \
  "${RESULT_DIR}" \
  "fosslight_yocto" \
  "${RESULT_DIR}/fosslight_report_yocto_pypi.xlsx" \
  "${RESULT_DIR}/fosslight_report_yocto_github.xlsx" \
  0
RC=$?
set -e
deactivate

if [[ "${KEEP_WORK}" != "1" ]]; then
  rm -rf "${PYPI_VENV}" "${GIT_VENV}"
fi

exit "${RC}"
