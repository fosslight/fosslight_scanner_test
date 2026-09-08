# FOSSLight Scanner Test

FOSSLight Scanner 계열 패키지를 자동으로 검증하는 저장소입니다. 목적은 두 가지입니다.

1. **PyPI vs GitHub Excel 비교** — 공개된 스캐너들이 PyPI 배포본과 GitHub `main` 개발 버전이 서로 다른 분석 결과를 내지 않는지 확인합니다. 동일 입력으로 스캔한 뒤, 생성된 Report Excel을 **시트별 셀 단위**로 비교합니다. (`Scanner Info` 시트는 제외)
2. **fosslight_dependency tox** — dependency scanner의 `tox -e run_ubuntu|run_windows|run_macos`를 매일 돌리되, `fosslight_util`은 **PyPI가 아니라 GitHub `main`**에서 설치해 최신 util과의 호환을 검증합니다.

## 이 Repository가 하는 일

| 구분 | 설명 |
|------|------|
| **목적** | (1) PyPI 설치본 vs GitHub 설치본의 스캔 결과 회귀 감지<br>(2) dependency tox + util@git main 호환성 검증 |
| **대상 도구** | `fosslight_scanner`, `fosslight_yocto`, `fosslight_dependency` (및 관련 util/source/binary 등) |
| **실행 주기** | 매일 — GitHub Actions<br>· 비교: 09:00 / 11:00 / 16:00 KST<br>· scanner build: 00:30 KST<br>· **dependency tox: 01:00 KST** |
| **결과 확인** | Actions Job Summary / Artifact<br>· 비교: `excel_diff` 표, 양쪽 Excel<br>· dependency tox: OS별 `tox_run_*.log`, `assert_dep_results.log`, `job_summary.md` |

### 포함 테스트

| Test | 내용 |
|------|------|
| **fosslight_scanner 비교** | PyPI vs GitHub 설치본 Excel 시트/셀 비교 (`Scanner Info` 제외) |
| **fosslight_yocto 비교** | PyPI vs GitHub 설치본 Excel 시트/셀 비교 (`Scanner Info` 제외) |
| **fosslight_scanner daily build** | GitHub `main` checkout → example 스캔 + `tox -e test_run` (Python 3.10–3.14) |
| **fosslight_dependency tox** | dependency `main` checkout → Ubuntu `run_ubuntu` **py3.10–3.14** + Windows/macOS **py3.14** + `DEP_FL_Dependency` non-empty assert (`fosslight_util`은 **GitHub main**, PyPI 아님) |

| Test | PyPI 설치 | GitHub 설치 | 실행 명령 |
|------|-----------|-------------|-----------|
| **fosslight_scanner** | `pip install fosslight_scanner` | util/source/dependency/binary/scanner/android/yocto (git) | `fosslight -w https://github.com/LGE-OSS/example` |
| **fosslight_yocto** | `pip install fosslight_yocto` | util/source/dependency/binary/scanner/android/yocto (git, scanner와 동일) | `fosslight_yocto -ip … -i … -b … -p … -y … -o test_result` |
| **fosslight_dependency tox** | (tox가 일시적으로 PyPI util을 깔 수 있음) | dependency checkout + tox env에 util **git force-reinstall** | `TOX_ENV=run_ubuntu|run_windows|run_macos` → `assert_dep_results.py --profile …` |

yocto 테스트 입력은 실행 시 [fosslight_yocto_scanner/test_files](https://github.com/fosslight/fosslight_yocto_scanner/tree/main/test_files)를 저장소 루트 `test_files/`로 받아 사용합니다.  
(`bom.json`, `installed-packages.txt`, `installed-package-names.txt`, `oss-pkg-info.yaml`, `packages/` 포함)

dependency tox fixture는 [fosslight_dependency_scanner/tests](https://github.com/fosslight/fosslight_dependency_scanner/tree/main/tests)를 사용합니다. (clone한 dependency 저장소의 `tests/` 트리)

### 성공 / 실패 기준

#### PyPI vs GitHub Excel 비교 (scanner / yocto)

| 비교 결과 | CI 결과 | 설명 |
|-----------|---------|------|
| **차이 없음** | ✅ Success | SRC/BIN/DEP 등 시트 셀 값 동일 |
| **차이 있음** | ❌ Failure | 시트·셀 차이를 Markdown 표로 출력 |

비교 방식:

- **시트별 셀 단위 비교** (`scripts/compare_excel.py`)
- **`Scanner Info` 시트는 제외** (실행시간·경로·버전 문구 등 변동 가능)
- `License`, `Depends On` 은 쉼표 구분 값을 정렬해 **순서만 다른 경우 동일** 처리
- `ID`, `TLSH` 컬럼은 비교에서 제외

표 컬럼: `# | Sheet | Type | Key | Column | PyPI | GitHub`

scanner / yocto Actions는 **서로 독립**이라, 한쪽 Failure가 다른 쪽 실행·결과에 영향을 주지 않습니다.

#### fosslight_dependency tox

| 결과 | CI 결과 | 설명 |
|------|---------|------|
| **tox 성공 + DEP assert 통과** | ✅ Success | 해당 OS tox 종료 코드 0, `--profile`별 필수 result의 `DEP_FL_Dependency` **non-empty row ≥ 2** |
| **tox 실패** | ❌ Failure | `tox_<env>.log`에 실패 원인 |
| **DEP assert 실패** | ❌ Failure | 필수 dir 누락, 리포트 없음, 시트 누락, 또는 row &lt; 2 |

dependency tox도 비교 workflow와 **독립**입니다. util은 항상 `git+https://github.com/fosslight/fosslight_util.git@main`으로 force-reinstall합니다.

전체 처리 흐름은 [docs/flowchart.md](docs/flowchart.md)를 참고하세요. (flowchart는 비교 테스트 중심이며, dependency tox는 아래 절차를 따릅니다.)

## 비교에 사용하는 패키지

### PyPI (기준선 — scanner / yocto 비교)

```bash
pip install fosslight_scanner   # scanner 테스트
pip install fosslight_yocto     # yocto 테스트
```

### GitHub (검증 대상)

- [fosslight_util](https://github.com/fosslight/fosslight_util) — **dependency tox에서는 이 저장소의 `main`만 사용** (PyPI util 사용 안 함)
- [fosslight_source_scanner](https://github.com/fosslight/fosslight_source_scanner)
- [fosslight_dependency_scanner](https://github.com/fosslight/fosslight_dependency_scanner)
- [fosslight_binary_scanner](https://github.com/fosslight/fosslight_binary_scanner)
- [fosslight_scanner](https://github.com/fosslight/fosslight_scanner)
- [fosslight_android_scanner](https://github.com/fosslight/fosslight_android_scanner)
- [fosslight_yocto_scanner](https://github.com/fosslight/fosslight_yocto_scanner)

## 테스트 절차 요약

### 1) fosslight_scanner

1. PyPI venv → `fosslight_scanner` 설치 → `fosslight -w https://github.com/LGE-OSS/example`
2. GitHub venv → 관련 패키지 설치 → 동일 명령 실행
3. Excel 시트/셀 비교 (`Scanner Info` 제외) → 표 출력

### 2) fosslight_yocto

1. PyPI venv → `fosslight_yocto` 설치
2. GitHub venv → scanner와 동일하게 util/source/dependency/binary/scanner/android/yocto를 git 설치
3. 동일 명령 실행:
   ```bash
   fosslight_yocto \
     -ip test_files/installed-packages.txt \
     -i test_files/installed-package-names.txt \
     -b test_files/bom.json \
     -p test_files/packages \
     -y test_files/oss-pkg-info.yaml \
     -o test_result
   ```
4. Excel 시트/셀 비교 (`Scanner Info` 제외) → 표 출력

비교 결과:

- 차이 없음 → 종료 코드 `0` (Success)
- 차이 있음 → 종료 코드 `1` (Failure) + 표 출력

### 3) fosslight_dependency tox

OS matrix: **Ubuntu** (`run_ubuntu`, Python **3.10–3.14**), **Windows** / **macOS** (`run_windows` / `run_macos`, Python **3.14**).

1. `fosslight_dependency_scanner` **main** clone (`DEP_REPO` / `DEP_REF`)
2. fixture 준비: Flutter `pub get`, Go `mod download` (ubuntu/windows), macOS는 `pod install`
3. `tox run -e $TOX_ENV --notest` — tox env만 생성 (이 단계에서 util이 PyPI로 깔릴 수 있음)
4. tox env에 `fosslight_util`을 **GitHub main으로 force-reinstall**
5. `tox run -e $TOX_ENV --skip-pkg-install` — util 재설치를 막고 fixture 테스트 실행
6. `scripts/assert_dep_results.py --profile ubuntu|windows|macos`로 필수 result dir의 DEP row ≥ 2 검사

환경 변수: `TOX_ENV`, `ASSERT_PROFILE`, `UTIL_GIT`, `DEP_REPO`, `DEP_REF`, `KEEP_WORK`
## 스케줄 (GitHub Actions)

테스트별로 **별도 workflow**로 실행됩니다.

| Workflow | 파일 | 스크립트 / 내용 |
|----------|------|-----------------|
| **Daily fosslight_scanner Test** | [`.github/workflows/daily_scanner_test.yml`](.github/workflows/daily_scanner_test.yml) | `scripts/run_scanner_test.sh` |
| **Daily fosslight_yocto Test** | [`.github/workflows/daily_yocto_test.yml`](.github/workflows/daily_yocto_test.yml) | `scripts/run_yocto_test.sh` |
| **Daily fosslight_scanner Build** | [`.github/workflows/daily_scanner_build.yml`](.github/workflows/daily_scanner_build.yml) | `fosslight/fosslight_scanner` main checkout → example 스캔 + tox |
| **Daily fosslight_dependency Tox** | [`.github/workflows/daily_dependency_tox.yml`](.github/workflows/daily_dependency_tox.yml) | `scripts/run_dependency_tox.sh` — Ubuntu py3.10–3.14 + Windows/macOS py3.14, util@git main |

| 시각 (KST) | cron | 대상 |
|------------|------|------|
| 09:00 / 11:00 / 16:00 | `0 9,11,16 * * *` (`Asia/Seoul`) | scanner / yocto 비교 |
| 09:00 | `0 0 * * *` (UTC) | scanner daily build |
| 09:00 | `0 0 * * *` (UTC) | Daily fosslight_dependency Tox |

수동 실행: Actions 탭에서 각 workflow의 **Run workflow** 로 개별 실행할 수 있습니다.

### 실패 알림 (Microsoft Teams)

workflow가 **Failure**이면 Teams 채널로 Adaptive Card 알림을 보냅니다.

- scanner / yocto 비교 실패 시 **Job Summary**(diff 표 포함)도 메시지에 첨부합니다. (길면 truncate)
- **dependency tox** 실패 시 `dependency_tox/job_summary.md`(tox/assert 요약)를 첨부합니다.

1. Teams 채널 → `…` → **워크플로** → 템플릿 **「웹후크 요청이 수신되면 채널에 게시」** (또는 **「채널에 웹후크 경고 보내기」**) 생성
2. 발급된 HTTP URL을 repository secret `TEAMS_WEBHOOK_URL` 에 등록  
   (Settings → Secrets and variables → Actions)
3. secret이 비어 있으면 알림은 **건너뛰고** CI 판정에는 영향을 주지 않습니다

알림 구현: [`.github/actions/notify-teams-failure`](.github/actions/notify-teams-failure)

## 로컬 실행

Python 3.10+ 가 필요합니다. (dependency tox는 tox·Java 17·npm `license-checker` 등 CI와 유사한 환경이 필요할 수 있습니다.)

```bash
chmod +x scripts/*.sh scripts/*.py
./scripts/run_scanner_test.sh        # scanner만
./scripts/run_yocto_test.sh          # yocto만
./scripts/run_dependency_tox.sh                 # ubuntu (default)
TOX_ENV=run_windows ASSERT_PROFILE=windows ./scripts/run_dependency_tox.sh
TOX_ENV=run_macos ASSERT_PROFILE=macos ./scripts/run_dependency_tox.sh
./scripts/run_daily_test.sh          # 로컬에서 scanner+yocto 실행 (선택)
```

#### `run_dependency_tox.sh` 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `UTIL_GIT` | `git+https://github.com/fosslight/fosslight_util.git@main` | tox env에 force-reinstall할 util 스펙 |
| `DEP_REPO` | `https://github.com/fosslight/fosslight_dependency_scanner.git` | dependency clone URL |
| `DEP_REF` | `main` | clone 브랜치/태그 |
| `KEEP_WORK` | `0` | `1`이면 `.work` venv 등 작업 디렉터리 유지 |
| `WORK_DIR` | `<repo>/.work` | clone·venv 작업 경로 |
| `RESULT_DIR` | `results/<timestamp>/dependency_tox` | 로그·요약 출력 경로 |

예:

```bash
UTIL_GIT='git+https://github.com/fosslight/fosslight_util.git@main' \
DEP_REF=main KEEP_WORK=1 \
./scripts/run_dependency_tox.sh
```

`run_dependency_tox.sh`는 [fosslight_dependency_scanner/tests](https://github.com/fosslight/fosslight_dependency_scanner/tree/main/tests) fixture로 `TOX_ENV`(기본 `run_ubuntu`)를 돌립니다.  
tox가 처음에 PyPI util을 깔 수 있으므로, 테스트 실행 전에 tox env에 `fosslight_util`을 **GitHub main으로 force-reinstall**한 뒤 `--skip-pkg-install`로 재설치를 막습니다. 이어서 `assert_dep_results.py --profile …`로 필수 DEP row ≥ 2를 검사합니다.

결과는 `results/<timestamp>/` 아래에 저장됩니다.

| 경로 | 설명 |
|------|------|
| `scanner/fosslight_report_pypi.xlsx` | scanner PyPI 결과 |
| `scanner/fosslight_report_github.xlsx` | scanner GitHub 결과 |
| `scanner/excel_diff.md` / `.json` | 시트/셀 비교 표 |
| `yocto/fosslight_report_yocto_pypi.xlsx` | yocto PyPI 결과 |
| `yocto/fosslight_report_yocto_github.xlsx` | yocto GitHub 결과 |
| `yocto/excel_diff.md` / `.json` | 시트/셀 비교 표 |
| `dependency_tox/<tox_env>/tox_*.log` | 해당 OS tox 전체 로그 |
| `dependency_tox/<tox_env>/assert_dep_results.log` | DEP 시트 non-empty assert 로그 |
| `dependency_tox/<tox_env>/job_summary.md` | Job Summary용 요약 (Teams 알림에도 사용) |

Excel만 따로 비교하려면:

```bash
python3 scripts/compare_excel.py path/to/pypi.xlsx path/to/github.xlsx --md diff.md
```

DEP 시트만 따로 검사하려면:

```bash
python3 scripts/assert_dep_results.py --profile ubuntu path/to/tests/result
```

## 디렉터리 구조

```text
fosslight_scanner_test/
├── .github/workflows/
│   ├── daily_scanner_test.yml      # fosslight_scanner PyPI vs GitHub 비교
│   ├── daily_yocto_test.yml        # fosslight_yocto PyPI vs GitHub 비교
│   ├── daily_scanner_build.yml     # fosslight_scanner main daily build + tox
│   └── daily_dependency_tox.yml    # dependency tox Ubuntu py3.10–3.14 + Win/macOS py3.14, util@git, 09:00 KST
├── docs/
├── scripts/
│   ├── common.sh
│   ├── compare_excel.py            # 시트/셀 단위 비교 → 표
│   ├── assert_dep_results.py       # DEP_FL_Dependency non-empty 검사
│   ├── run_scanner_test.sh
│   ├── run_yocto_test.sh
│   ├── run_dependency_tox.sh       # dependency tox + util@git
│   ├── run_daily_test.sh           # 로컬 scanner+yocto (선택)
│   └── run_fosslight_compare.py    # (optional) BOM compare
├── README.md
└── LICENSE
```

## License

Apache-2.0
