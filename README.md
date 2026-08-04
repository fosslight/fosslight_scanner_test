# FOSSLight Scanner Test

FOSSLight Scanner 계열 패키지의 **PyPI 배포본**과 **GitHub 최신 소스** 결과가 같은지 자동으로 검증하는 저장소입니다.

공개된 FOSSLight 스캐너들이 PyPI에 올라간 버전과 GitHub `main` 개발 버전이 서로 다른 분석 결과를 내지 않는지 확인하는 것이 목적입니다.  
동일 입력으로 스캔한 뒤, 생성된 Report Excel을 **시트별 셀 단위**로 비교하고 결과를 표로 출력합니다. (`Scanner Info` 시트는 제외)

## 이 Repository가 하는 일

| 구분 | 설명 |
|------|------|
| **목적** | PyPI 설치본 vs GitHub 설치본의 스캔 결과 회귀(regression) 감지 |
| **대상 도구** | `fosslight_scanner`, `fosslight_yocto` (및 관련 util/source/binary 등) |
| **실행 주기** | 매일 오전 9시, 11시, 오후 4시 (KST) — GitHub Actions |
| **결과 확인** | Actions Job Summary / Artifact (`excel_diff` 표, 양쪽 Excel) |

### 포함 테스트

| Test | PyPI 설치 | GitHub 설치 | 실행 명령 |
|------|-----------|-------------|-----------|
| **fosslight_scanner** | `pip install fosslight_scanner` | util/source/dependency/binary/scanner/android/yocto (git) | `fosslight -w https://github.com/LGE-OSS/example` |
| **fosslight_yocto** | `pip install fosslight_yocto` | util/source/dependency/binary/scanner/android/yocto (git, scanner와 동일) | `fosslight_yocto -ip … -i … -b … -p … -y … -o test_result` |

yocto 테스트 입력은 실행 시 [fosslight_yocto_scanner/test_files](https://github.com/fosslight/fosslight_yocto_scanner/tree/main/test_files)를 저장소 루트 `test_files/`로 받아 사용합니다.  
(`bom.json`, `installed-packages.txt`, `installed-package-names.txt`, `oss-pkg-info.yaml`, `packages/` 포함)

### 성공 / 실패 기준

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

전체 처리 흐름은 [docs/flowchart.md](docs/flowchart.md)를 참고하세요.

## 비교에 사용하는 패키지

### PyPI (기준선)

```bash
pip install fosslight_scanner   # scanner 테스트
pip install fosslight_yocto     # yocto 테스트
```

### GitHub (검증 대상)

- [fosslight_util](https://github.com/fosslight/fosslight_util)
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

## 스케줄 (GitHub Actions)

테스트별로 **별도 workflow**로 실행됩니다.

| Workflow | 파일 | 스크립트 |
|----------|------|----------|
| **Daily fosslight_scanner Test** | [`.github/workflows/daily_scanner_test.yml`](.github/workflows/daily_scanner_test.yml) | `scripts/run_scanner_test.sh` |
| **Daily fosslight_yocto Test** | [`.github/workflows/daily_yocto_test.yml`](.github/workflows/daily_yocto_test.yml) | `scripts/run_yocto_test.sh` |

| 시각 (KST) | cron |
|------------|------|
| 09:00 | `0 9 * * *` |
| 11:00 | `0 11 * * *` |
| 16:00 | `0 16 * * *` |

타임존: `Asia/Seoul`  
수동 실행: Actions 탭에서 각 workflow의 **Run workflow** 로 개별 실행할 수 있습니다.

## 로컬 실행

Python 3.10+ 가 필요합니다.

```bash
chmod +x scripts/*.sh scripts/*.py
./scripts/run_scanner_test.sh        # scanner만
./scripts/run_yocto_test.sh          # yocto만
./scripts/run_daily_test.sh          # 로컬에서 둘 다 실행 (선택)
```

결과는 `results/<timestamp>/` 아래에 저장됩니다.

| 경로 | 설명 |
|------|------|
| `scanner/fosslight_report_pypi.xlsx` | scanner PyPI 결과 |
| `scanner/fosslight_report_github.xlsx` | scanner GitHub 결과 |
| `scanner/excel_diff.md` / `.json` | 시트/셀 비교 표 |
| `yocto/fosslight_report_yocto_pypi.xlsx` | yocto PyPI 결과 |
| `yocto/fosslight_report_yocto_github.xlsx` | yocto GitHub 결과 |
| `yocto/excel_diff.md` / `.json` | 시트/셀 비교 표 |

Excel만 따로 비교하려면:

```bash
python3 scripts/compare_excel.py path/to/pypi.xlsx path/to/github.xlsx --md diff.md
```

## 디렉터리 구조

```text
fosslight_scanner_test/
├── .github/workflows/
│   ├── daily_scanner_test.yml    # fosslight_scanner CI
│   └── daily_yocto_test.yml      # fosslight_yocto CI
├── docs/
├── scripts/
│   ├── common.sh
│   ├── compare_excel.py          # 시트/셀 단위 비교 → 표
│   ├── run_scanner_test.sh
│   ├── run_yocto_test.sh
│   ├── run_daily_test.sh         # 로컬 전체 실행(선택)
│   └── run_fosslight_compare.py  # (optional) BOM compare
├── README.md
└── LICENSE
```

## License

Apache-2.0
