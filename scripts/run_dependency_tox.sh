#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run fosslight_dependency tox with fosslight_util from GitHub main (not PyPI).
#
# Env:
#   TOX_ENV          run_ubuntu | run_windows | run_macos  (default: run_ubuntu)
#   ASSERT_PROFILE   ubuntu | windows | macos              (default: derived from TOX_ENV)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/scripts/common.sh"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/.work}"
RESULT_DIR="${RESULT_DIR:-${ROOT_DIR}/results/$(date +%Y%m%d_%H%M%S)/dependency_tox}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
KEEP_WORK="${KEEP_WORK:-0}"

DEP_REPO="${DEP_REPO:-https://github.com/fosslight/fosslight_dependency_scanner.git}"
DEP_REF="${DEP_REF:-main}"
UTIL_GIT="${UTIL_GIT:-git+https://github.com/fosslight/fosslight_util.git@main}"
TOX_ENV="${TOX_ENV:-run_ubuntu}"

case "${TOX_ENV}" in
  run_ubuntu) DEFAULT_PROFILE=ubuntu ;;
  run_windows) DEFAULT_PROFILE=windows ;;
  run_macos) DEFAULT_PROFILE=macos ;;
  *)
    echo "ERROR: unsupported TOX_ENV=${TOX_ENV} (use run_ubuntu|run_windows|run_macos)" >&2
    exit 2
    ;;
esac
ASSERT_PROFILE="${ASSERT_PROFILE:-${DEFAULT_PROFILE}}"

DEP_DIR="${WORK_DIR}/fosslight_dependency_scanner"
VENV_DIR="${WORK_DIR}/venv_dependency_tox_${TOX_ENV}"
COCOAPODS_PROJECT="tests/test_cocoapods/cocoapods-tips/JWSCocoapodsTips"

mkdir -p "${WORK_DIR}" "${RESULT_DIR}"
log "Result directory: ${RESULT_DIR}"
log "dependency: ${DEP_REPO}@${DEP_REF}"
log "fosslight_util: ${UTIL_GIT}"
log "tox env: ${TOX_ENV} (assert profile: ${ASSERT_PROFILE})"

log "Creating virtualenv for tox host"
create_venv "${VENV_DIR}" "${PYTHON_BIN}"
# shellcheck disable=SC1090
source "${VENV_DIR}/bin/activate"
python -m pip install --upgrade pip setuptools wheel tox openpyxl

log "Cloning fosslight_dependency_scanner (${DEP_REF})"
rm -rf "${DEP_DIR}"
git clone --depth 1 --branch "${DEP_REF}" "${DEP_REPO}" "${DEP_DIR}"

cd "${DEP_DIR}"
log "Checked out dependency at $(git rev-parse --short HEAD)"

if command -v flutter >/dev/null 2>&1; then
  log "Flutter pub get for fixtures"
  flutter --version
  (cd tests/test_pub && flutter pub get)
  (cd tests/test_exclude && flutter pub get)
else
  log "WARNING: flutter not on PATH; pub tests may produce empty DEP sheets"
fi

if command -v go >/dev/null 2>&1; then
  log "Go mod download for fixtures"
  go version
  (cd tests/test_mod && go mod download)
else
  log "WARNING: go not on PATH; mod tests may produce empty DEP sheets"
fi

if [[ "${TOX_ENV}" == "run_ubuntu" ]] && command -v helm >/dev/null 2>&1; then
  log "Helm repo add for fixtures"
  helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
  helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
  helm repo update
elif [[ "${TOX_ENV}" == "run_ubuntu" ]]; then
  log "WARNING: helm not on PATH; helm tests may produce empty DEP sheets"
fi

if [[ "${TOX_ENV}" == "run_macos" ]]; then
  if ! command -v pod >/dev/null 2>&1; then
    echo "ERROR: pod not found; CocoaPods is required for run_macos" >&2
    exit 2
  fi
  log "pod install for CocoaPods fixture"
  (cd "${COCOAPODS_PROJECT}" && pod install --clean-install)
fi

log "Creating tox env ${TOX_ENV} (install only; util may come from PyPI here)"
tox run -e "${TOX_ENV}" --notest

TOX_ENV_DIR="$(TOX_ENV_NAME="${TOX_ENV}" python - <<'PY'
import os
from pathlib import Path
name = os.environ["TOX_ENV_NAME"]
candidates = [
    Path("tests") / name,
    Path("tests") / ".tox" / name,
    Path(".tox") / name,
]
for path in candidates:
    # Unix and Windows venv layouts
    if (path / "bin" / "python").is_file() or (path / "Scripts" / "python.exe").is_file():
        print(path.resolve())
        break
else:
    raise SystemExit(f"tox env {name} not found under tests/{name}, tests/.tox, or .tox/")
PY
)"
log "Tox env: ${TOX_ENV_DIR}"

if [[ -x "${TOX_ENV_DIR}/bin/pip" ]]; then
  TOX_PIP="${TOX_ENV_DIR}/bin/pip"
  TOX_PYTHON="${TOX_ENV_DIR}/bin/python"
elif [[ -f "${TOX_ENV_DIR}/Scripts/pip.exe" ]]; then
  TOX_PIP="${TOX_ENV_DIR}/Scripts/pip.exe"
  TOX_PYTHON="${TOX_ENV_DIR}/Scripts/python.exe"
else
  echo "ERROR: pip/python not found in ${TOX_ENV_DIR}" >&2
  exit 2
fi

log "Force-installing fosslight_util from GitHub main into tox env"
"${TOX_PIP}" install --upgrade --force-reinstall "${UTIL_GIT}"

log "Installed package versions (tox env)"
"${TOX_PYTHON}" - <<'PY'
from importlib.metadata import PackageNotFoundError, version
for pkg in ("fosslight_dependency", "fosslight_util"):
    try:
        print(f"  {pkg}: {version(pkg)}")
    except PackageNotFoundError:
        print(f"  {pkg}: (not installed)")
import fosslight_util
print(f"  fosslight_util file: {fosslight_util.__file__}")
PY

LOG_NAME="tox_${TOX_ENV}.log"
log "Running tox ${TOX_ENV} with --skip-pkg-install (keep util from git)"
set +e
FOSSLIGHT_PRESERVE_DAILY_TEST_RESULTS=1 tox run -e "${TOX_ENV}" --skip-pkg-install 2>&1 | tee "${RESULT_DIR}/${LOG_NAME}"
TOX_RC=${PIPESTATUS[0]}
set -e

log "Asserting DEP_FL_Dependency sheets under tests/result (profile=${ASSERT_PROFILE})"
set +e
python "${ROOT_DIR}/scripts/assert_dep_results.py" \
  --profile "${ASSERT_PROFILE}" \
  "${DEP_DIR}/tests/result" 2>&1 | tee "${RESULT_DIR}/assert_dep_results.log"
ASSERT_RC=${PIPESTATUS[0]}
set -e

log "Removing preserved dependency test results"
rm -rf "${DEP_DIR}/tests/result"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    if [[ "${TOX_RC}" -eq 0 && "${ASSERT_RC}" -eq 0 ]]; then
      echo "## ✅ fosslight_dependency tox (${TOX_ENV}, util@git main): Success"
    else
      echo "## ❌ fosslight_dependency tox (${TOX_ENV}, util@git main): Failure"
    fi
    echo ""
    echo "- dependency: \`${DEP_REPO}@${DEP_REF}\` (\`$(git rev-parse --short HEAD)\`)"
    echo "- fosslight_util: \`${UTIL_GIT}\`"
    echo "- tox env: \`${TOX_ENV}\`"
    echo "- assert profile: \`${ASSERT_PROFILE}\`"
    echo "- tox run exit: \`${TOX_RC}\`"
    echo "- DEP sheet assert exit: \`${ASSERT_RC}\`"
    echo ""
    echo "### DEP sheet assert"
    echo '```'
    tail -n 80 "${RESULT_DIR}/assert_dep_results.log" || true
    echo '```'
  } | tee "${RESULT_DIR}/job_summary.md" >> "${GITHUB_STEP_SUMMARY}"
else
  {
    echo "tox_env=${TOX_ENV}"
    echo "assert_profile=${ASSERT_PROFILE}"
    echo "tox_rc=${TOX_RC}"
    echo "assert_rc=${ASSERT_RC}"
  } > "${RESULT_DIR}/job_summary.md"
fi

deactivate
if [[ "${KEEP_WORK}" != "1" ]]; then
  rm -rf "${VENV_DIR}"
fi

if [[ "${TOX_RC}" -ne 0 ]]; then
  log "FAILURE: tox failed (rc=${TOX_RC})"
  exit "${TOX_RC}"
fi
if [[ "${ASSERT_RC}" -ne 0 ]]; then
  log "FAILURE: DEP sheet assert failed (rc=${ASSERT_RC})"
  exit "${ASSERT_RC}"
fi

log "SUCCESS: dependency tox (${TOX_ENV}) + DEP sheet assert passed"
exit 0
