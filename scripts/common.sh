#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Shared helpers for PyPI vs GitHub comparison tests.

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# Shared GitHub installs for PyPI-vs-Git comparison (subpackages from git main).
GIT_PACKAGES=(
  "git+https://github.com/fosslight/fosslight_util.git"
  "git+https://github.com/fosslight/fosslight_source_scanner.git"
  "git+https://github.com/fosslight/fosslight_dependency_scanner.git"
  "git+https://github.com/fosslight/fosslight_binary_scanner.git"
  "git+https://github.com/fosslight/fosslight_scanner.git"
  "git+https://github.com/fosslight/fosslight_android_scanner.git"
  "git+https://github.com/fosslight/fosslight_yocto_scanner.git"
)

create_venv() {
  local venv_dir="$1"
  local python_bin="${2:-python3}"
  rm -rf "${venv_dir}"
  "${python_bin}" -m venv "${venv_dir}"
  # shellcheck disable=SC1090
  source "${venv_dir}/bin/activate"
  python -m pip install --upgrade pip setuptools wheel
  deactivate
}

find_excel() {
  # Usage: find_excel <dir> <pattern> [pattern...]
  local search_dir="$1"
  shift
  local pattern excel=""
  for pattern in "$@"; do
    excel="$(find "${search_dir}" -type f -name "${pattern}" | sort | tail -n 1 || true)"
    if [[ -n "${excel}" ]]; then
      printf '%s\n' "${excel}"
      return 0
    fi
  done
  echo "ERROR: Excel matching ($*) not found under ${search_dir}" >&2
  find "${search_dir}" -type f | sort >&2 || true
  return 1
}

print_package_versions() {
  local label="$1"
  shift
  log "Installed package versions (${label}):"
  PRINT_PKGS="$*" python - <<'PY'
import os
from importlib.metadata import PackageNotFoundError, version

for pkg in os.environ.get("PRINT_PKGS", "").split():
    try:
        print(f"  {pkg}: {version(pkg)}")
    except PackageNotFoundError:
        print(f"  {pkg}: (not installed)")
PY
}

compare_excels() {
  # Args: root_dir result_dir label pypi_excel github_excel
  # Compare with fosslight-compare logic and print BOM result as a Markdown table.
  local root_dir="$1"
  local result_dir="$2"
  local label="$3"
  local pypi_excel="$4"
  local github_excel="$5"

  local compare_json="${result_dir}/fosslight_compare.json"
  local compare_md="${result_dir}/fosslight_compare.md"
  local compare_txt="${result_dir}/fosslight_compare.txt"
  local diff_rc=0

  mkdir -p "${result_dir}"

  # Optional: also produce official CLI artifacts when fosslight is available
  if command -v fosslight >/dev/null 2>&1; then
    log "[${label}] Running fosslight compare CLI (artifact)"
    local compare_out="${result_dir}/fosslight_compare_cli"
    mkdir -p "${compare_out}"
    set +e
    fosslight compare \
      -p "${pypi_excel}" "${github_excel}" \
      -o "${compare_out}" \
      -f excel json \
      -t
    set -e
  fi

  log "[${label}] Formatting fosslight compare BOM result as table"
  set +e
  python "${root_dir}/scripts/run_fosslight_compare.py" \
    "${pypi_excel}" \
    "${github_excel}" \
    -o "${compare_json}" \
    --md "${compare_md}" | tee "${compare_txt}"
  diff_rc=$?
  set -e

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      if [[ "${diff_rc}" -eq 0 ]]; then
        echo "## ✅ ${label}: Success — fosslight compare: no BOM differences"
      else
        echo "## ❌ ${label}: Failure — fosslight compare found BOM differences"
      fi
      echo ""
      echo "- PyPI (before): \`$(basename "${pypi_excel}")\`"
      echo "- GitHub (after): \`$(basename "${github_excel}")\`"
      echo "- Compare exit code: \`${diff_rc}\` (0=동일/Success, 1=차이/Failure)"
      echo ""
      echo "### fosslight compare result"
      echo ""
      if [[ -f "${compare_md}" ]]; then
        cat "${compare_md}"
      else
        cat "${compare_txt}"
      fi
      echo ""
    } >> "${GITHUB_STEP_SUMMARY}"
  fi

  if [[ "${diff_rc}" -ne 0 ]]; then
    log "[${label}] FAILURE: fosslight compare found differences. Review: ${compare_txt}"
    log "---- ${label} compare begin ----"
    cat "${compare_txt}" || true
    log "---- ${label} compare end ----"
    return 1
  fi

  log "[${label}] SUCCESS: fosslight compare — no BOM differences."
  return 0
}

fetch_yocto_test_files() {
  # Populate dest_dir with https://github.com/fosslight/fosslight_yocto_scanner/tree/main/test_files
  local dest_dir="$1"
  local cache_parent="${2:-$(dirname "${dest_dir}")/.work}"
  local repo_dir="${cache_parent}/fosslight_yocto_scanner"
  local required=(
    "installed-packages.txt"
    "installed-package-names.txt"
    "bom.json"
    "oss-pkg-info.yaml"
    "packages"
  )

  local missing=0
  if [[ -d "${dest_dir}" ]]; then
    for name in "${required[@]}"; do
      if [[ ! -e "${dest_dir}/${name}" ]]; then
        missing=1
        break
      fi
    done
  else
    missing=1
  fi

  if [[ "${missing}" -eq 0 ]]; then
    log "Using yocto test_files at ${dest_dir}"
    log "Source: https://github.com/fosslight/fosslight_yocto_scanner/tree/main/test_files"
    return 0
  fi

  log "Fetching test_files from fosslight/fosslight_yocto_scanner (main)"
  log "URL: https://github.com/fosslight/fosslight_yocto_scanner/tree/main/test_files"
  mkdir -p "${cache_parent}"
  rm -rf "${repo_dir}"
  git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/fosslight/fosslight_yocto_scanner.git \
    "${repo_dir}"
  git -C "${repo_dir}" sparse-checkout set test_files
  # Ensure blobs for test_files are materialized
  git -C "${repo_dir}" checkout HEAD -- test_files

  for name in "${required[@]}"; do
    if [[ ! -e "${repo_dir}/test_files/${name}" ]]; then
      echo "ERROR: required test_files/${name} missing after checkout" >&2
      find "${repo_dir}/test_files" -maxdepth 2 | head -n 50 >&2 || true
      return 1
    fi
  done

  rm -rf "${dest_dir}"
  mkdir -p "$(dirname "${dest_dir}")"
  # Prefer a real directory copy for stable relative paths in the yocto command
  cp -a "${repo_dir}/test_files" "${dest_dir}"
  log "Yocto test_files ready: ${dest_dir}"
}
