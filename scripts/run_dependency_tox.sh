#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run fosslight_dependency tox (ubuntu) with fosslight_util from GitHub main (not PyPI).
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

DEP_DIR="${WORK_DIR}/fosslight_dependency_scanner"
VENV_DIR="${WORK_DIR}/venv_dependency_tox"

mkdir -p "${WORK_DIR}" "${RESULT_DIR}"
log "Result directory: ${RESULT_DIR}"
log "dependency: ${DEP_REPO}@${DEP_REF}"
log "fosslight_util: ${UTIL_GIT}"

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

log "Creating tox env run_ubuntu (install only; util may come from PyPI here)"
tox run -e run_ubuntu --notest

TOX_ENV_DIR="$(python - <<'PY'
from pathlib import Path
candidates = [
    Path("tests") / "run_ubuntu",
    Path("tests") / ".tox" / "run_ubuntu",
    Path(".tox") / "run_ubuntu",
]
for path in candidates:
    if (path / "bin" / "python").is_file():
        print(path.resolve())
        break
else:
    raise SystemExit("tox run_ubuntu env not found under tests/run_ubuntu, tests/.tox, or .tox/")
PY
)"
log "Tox env: ${TOX_ENV_DIR}"

log "Force-installing fosslight_util from GitHub main into tox env"
"${TOX_ENV_DIR}/bin/pip" install --upgrade --force-reinstall "${UTIL_GIT}"

log "Installed package versions (tox env)"
"${TOX_ENV_DIR}/bin/python" - <<'PY'
from importlib.metadata import PackageNotFoundError, version
for pkg in ("fosslight_dependency", "fosslight_util"):
    try:
        print(f"  {pkg}: {version(pkg)}")
    except PackageNotFoundError:
        print(f"  {pkg}: (not installed)")
import fosslight_util
print(f"  fosslight_util file: {fosslight_util.__file__}")
PY

log "Running tox run_ubuntu with --skip-pkg-install (keep util from git)"
set +e
tox run -e run_ubuntu --skip-pkg-install 2>&1 | tee "${RESULT_DIR}/tox_ubuntu.log"
TOX_RC=${PIPESTATUS[0]}
set -e

log "Asserting DEP_FL_Dependency sheets under tests/result have data rows"
set +e
python "${ROOT_DIR}/scripts/assert_dep_results.py" "${DEP_DIR}/tests/result" 2>&1 | tee "${RESULT_DIR}/assert_dep_results.log"
ASSERT_RC=${PIPESTATUS[0]}
set -e

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    if [[ "${TOX_RC}" -eq 0 && "${ASSERT_RC}" -eq 0 ]]; then
      echo "## ✅ fosslight_dependency tox (util@git main): Success"
    else
      echo "## ❌ fosslight_dependency tox (util@git main): Failure"
    fi
    echo ""
    echo "- dependency: \`${DEP_REPO}@${DEP_REF}\` (\`$(git rev-parse --short HEAD)\`)"
    echo "- fosslight_util: \`${UTIL_GIT}\`"
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

log "SUCCESS: dependency tox + DEP sheet assert passed"
exit 0
