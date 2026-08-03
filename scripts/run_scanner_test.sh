#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run fosslight against LGE-OSS/example with PyPI vs GitHub installs, then compare Excels.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/scripts/common.sh"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/.work}"
BASE_RESULT_DIR="${RESULT_DIR:-${ROOT_DIR}/results/$(date +%Y%m%d_%H%M%S)}"
# Scanner outputs go under scanner/ subdir when RESULT_DIR is provided by CI
SCANNER_RESULT_DIR="${BASE_RESULT_DIR}/scanner"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SCAN_URL="${SCAN_URL:-https://github.com/LGE-OSS/example}"
KEEP_WORK="${KEEP_WORK:-0}"

PYPI_VENV="${WORK_DIR}/venv_scanner_pypi"
GIT_VENV="${WORK_DIR}/venv_scanner_git"
PYPI_OUT="${SCANNER_RESULT_DIR}/pypi"
GIT_OUT="${SCANNER_RESULT_DIR}/github"

run_scan() {
  local out_dir="$1"
  mkdir -p "${out_dir}"
  log "Running: fosslight -w ${SCAN_URL} -o ${out_dir} -t"
  fosslight -w "${SCAN_URL}" -o "${out_dir}" -t
}

mkdir -p "${WORK_DIR}" "${SCANNER_RESULT_DIR}"
log "Scanner result directory: ${SCANNER_RESULT_DIR}"

# --- PyPI baseline ---
log "Creating PyPI virtualenv"
create_venv "${PYPI_VENV}" "${PYTHON_BIN}"
# shellcheck disable=SC1090
source "${PYPI_VENV}/bin/activate"
log "Installing fosslight_scanner from PyPI"
python -m pip install fosslight_scanner
print_package_versions "scanner-PyPI" \
  fosslight_scanner fosslight_source fosslight_dependency fosslight_binary fosslight_util
run_scan "${PYPI_OUT}"
# Current fosslight_scanner writes fosslight_report_all_*.xlsx
PYPI_EXCEL="$(find_excel "${PYPI_OUT}" 'fosslight_report*.xlsx' 'FOSSLight-Report*.xlsx')"
log "PyPI excel: ${PYPI_EXCEL}"
cp -f "${PYPI_EXCEL}" "${SCANNER_RESULT_DIR}/fosslight_report_pypi.xlsx"
deactivate

# --- GitHub packages ---
log "Creating GitHub virtualenv"
create_venv "${GIT_VENV}" "${PYTHON_BIN}"
# shellcheck disable=SC1090
source "${GIT_VENV}/bin/activate"
log "Installing FOSSLight packages from GitHub repositories"
python -m pip install "${GIT_PACKAGES[@]}"
print_package_versions "scanner-GitHub" \
  fosslight_scanner fosslight_source fosslight_dependency fosslight_binary \
  fosslight_util fosslight_android fosslight_yocto
run_scan "${GIT_OUT}"
GIT_EXCEL="$(find_excel "${GIT_OUT}" 'fosslight_report*.xlsx' 'FOSSLight-Report*.xlsx')"
log "GitHub excel: ${GIT_EXCEL}"
cp -f "${GIT_EXCEL}" "${SCANNER_RESULT_DIR}/fosslight_report_github.xlsx"

# --- Compare ---
set +e
compare_excels \
  "${ROOT_DIR}" \
  "${SCANNER_RESULT_DIR}" \
  "fosslight_scanner" \
  "${SCANNER_RESULT_DIR}/fosslight_report_pypi.xlsx" \
  "${SCANNER_RESULT_DIR}/fosslight_report_github.xlsx" \
  1
RC=$?
set -e
deactivate

if [[ "${KEEP_WORK}" != "1" ]]; then
  rm -rf "${PYPI_VENV}" "${GIT_VENV}"
fi

exit "${RC}"
