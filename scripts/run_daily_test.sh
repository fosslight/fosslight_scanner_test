#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run fosslight against LGE-OSS/example with PyPI vs GitHub installs, then compare Excels.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/.work}"
RESULT_DIR="${RESULT_DIR:-${ROOT_DIR}/results/$(date +%Y%m%d_%H%M%S)}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SCAN_URL="${SCAN_URL:-https://github.com/LGE-OSS/example}"
KEEP_WORK="${KEEP_WORK:-0}"

PYPI_VENV="${WORK_DIR}/venv_pypi"
GIT_VENV="${WORK_DIR}/venv_git"
PYPI_OUT="${RESULT_DIR}/pypi"
GIT_OUT="${RESULT_DIR}/github"

GIT_PACKAGES=(
  "git+https://github.com/fosslight/fosslight_util.git"
  "git+https://github.com/fosslight/fosslight_source_scanner.git"
  "git+https://github.com/fosslight/fosslight_dependency_scanner.git"
  "git+https://github.com/fosslight/fosslight_binary_scanner.git"
  "git+https://github.com/fosslight/fosslight_scanner.git"
  "git+https://github.com/fosslight/fosslight_android_scanner.git"
  "git+https://github.com/fosslight/fosslight_yocto_scanner.git"
)

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

find_report_excel() {
  local search_dir="$1"
  local excel
  excel="$(find "${search_dir}" -type f -name 'FOSSLight-Report*.xlsx' | sort | tail -n 1 || true)"
  if [[ -z "${excel}" ]]; then
    echo "ERROR: FOSSLight Report excel not found under ${search_dir}" >&2
    find "${search_dir}" -type f | sort >&2 || true
    return 1
  fi
  printf '%s\n' "${excel}"
}

create_venv() {
  local venv_dir="$1"
  rm -rf "${venv_dir}"
  "${PYTHON_BIN}" -m venv "${venv_dir}"
  # shellcheck disable=SC1090
  source "${venv_dir}/bin/activate"
  python -m pip install --upgrade pip setuptools wheel
  deactivate
}

print_versions() {
  local label="$1"
  log "Installed package versions (${label}):"
  python - <<'PY'
from importlib.metadata import version, PackageNotFoundError
pkgs = [
    "fosslight_scanner",
    "fosslight_source",
    "fosslight_dependency",
    "fosslight_binary",
    "fosslight_util",
    "fosslight_android",
    "fosslight_yocto",
]
for pkg in pkgs:
    try:
        print(f"  {pkg}: {version(pkg)}")
    except PackageNotFoundError:
        print(f"  {pkg}: (not installed)")
PY
}

run_scan() {
  local out_dir="$1"
  mkdir -p "${out_dir}"
  log "Running: fosslight -w ${SCAN_URL} -o ${out_dir} -t"
  fosslight -w "${SCAN_URL}" -o "${out_dir}" -t
}

mkdir -p "${WORK_DIR}" "${RESULT_DIR}"
log "Result directory: ${RESULT_DIR}"

# --- PyPI baseline ---
log "Creating PyPI virtualenv"
create_venv "${PYPI_VENV}"
# shellcheck disable=SC1090
source "${PYPI_VENV}/bin/activate"
log "Installing fosslight_scanner from PyPI"
python -m pip install fosslight_scanner
print_versions "PyPI"
run_scan "${PYPI_OUT}"
PYPI_EXCEL="$(find_report_excel "${PYPI_OUT}")"
log "PyPI excel: ${PYPI_EXCEL}"
cp -f "${PYPI_EXCEL}" "${RESULT_DIR}/FOSSLight-Report_pypi.xlsx"
deactivate

# --- GitHub packages ---
log "Creating GitHub virtualenv"
create_venv "${GIT_VENV}"
# shellcheck disable=SC1090
source "${GIT_VENV}/bin/activate"
log "Installing FOSSLight packages from GitHub repositories"
python -m pip install "${GIT_PACKAGES[@]}"
print_versions "GitHub"
run_scan "${GIT_OUT}"
GIT_EXCEL="$(find_report_excel "${GIT_OUT}")"
log "GitHub excel: ${GIT_EXCEL}"
cp -f "${GIT_EXCEL}" "${RESULT_DIR}/FOSSLight-Report_github.xlsx"
deactivate

# --- Compare ---
# shellcheck disable=SC1090
source "${GIT_VENV}/bin/activate"
log "Running fosslight compare (BOM-level)"
COMPARE_OUT="${RESULT_DIR}/fosslight_compare"
mkdir -p "${COMPARE_OUT}"
set +e
fosslight compare \
  -p "${RESULT_DIR}/FOSSLight-Report_pypi.xlsx" "${RESULT_DIR}/FOSSLight-Report_github.xlsx" \
  -o "${COMPARE_OUT}" \
  -f excel json \
  -t
COMPARE_RC=$?
set -e

log "Running cell-level Excel comparison"
DIFF_JSON="${RESULT_DIR}/excel_diff.json"
DIFF_TXT="${RESULT_DIR}/excel_diff.txt"
set +e
python "${ROOT_DIR}/scripts/compare_excel.py" \
  "${RESULT_DIR}/FOSSLight-Report_pypi.xlsx" \
  "${RESULT_DIR}/FOSSLight-Report_github.xlsx" \
  -o "${DIFF_JSON}" | tee "${DIFF_TXT}"
DIFF_RC=$?
set -e
deactivate

# Summary for GitHub Actions job summary if available
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    if [[ "${DIFF_RC}" -eq 0 ]]; then
      echo "## ✅ Success — no Excel differences (PyPI == GitHub)"
    else
      echo "## ❌ Failure — Excel differences found (PyPI != GitHub)"
    fi
    echo ""
    echo "- Scan URL: \`${SCAN_URL}\`"
    echo "- PyPI report: \`FOSSLight-Report_pypi.xlsx\`"
    echo "- GitHub report: \`FOSSLight-Report_github.xlsx\`"
    echo "- Cell-level diff exit code: \`${DIFF_RC}\` (0=동일/Success, 1=차이/Failure)"
    echo "- fosslight compare exit code: \`${COMPARE_RC}\`"
    echo ""
    echo "### Diff output"
    echo ""
    echo '```'
    sed -n '1,200p' "${DIFF_TXT}"
    echo '```'
  } >> "${GITHUB_STEP_SUMMARY}"
fi

if [[ "${KEEP_WORK}" != "1" ]]; then
  rm -rf "${WORK_DIR}"
fi

# Pass/Fail: 차이 없음 = Success, 차이 있음 = Failure (+ diff already printed above)
if [[ "${DIFF_RC}" -ne 0 ]]; then
  log "FAILURE: differences detected. Review: ${DIFF_TXT}"
  log "---- diff begin ----"
  cat "${DIFF_TXT}" || true
  log "---- diff end ----"
  exit 1
fi

log "SUCCESS: no Excel differences detected (PyPI and GitHub results match)."
exit 0
