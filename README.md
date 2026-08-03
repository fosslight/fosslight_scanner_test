# FOSSLight Scanner Test

FOSSLight Scanner 계열 패키지의 **PyPI 배포본**과 **GitHub 최신 소스** 결과가 같은지 자동으로 검증하는 저장소입니다.

공개된 FOSSLight 스캐너들이 PyPI에 올라간 버전과 GitHub `main` 개발 버전이 서로 다른 분석 결과를 내지 않는지 확인하는 것이 목적입니다.  
같은 입력([LGE-OSS/example](https://github.com/LGE-OSS/example))으로 스캔한 뒤, 생성된 FOSSLight Report Excel을 비교해 달라진 값을 출력합니다.

## 이 Repository가 하는 일

| 구분 | 설명 |
|------|------|
| **목적** | PyPI 설치본 vs GitHub 설치본의 스캔 결과(Excel) 회귀(regression) 감지 |
| **대상 도구** | FOSSLight Scanner 및 관련 패키지 (util, source, dependency, binary, android, yocto) |
| **테스트 입력** | `fosslight -w https://github.com/LGE-OSS/example` |
| **비교 대상** | 각 설치 방식으로 생성된 `FOSSLight-Report_*.xlsx` |
| **실행 주기** | 매일 오전 9시, 11시, 오후 4시 (KST) — GitHub Actions |
| **결과 확인** | Actions Job Summary / Artifact (`excel_diff`, 양쪽 Excel, `fosslight compare` 결과) |

### 성공 / 실패 기준

| 비교 결과 | CI 결과 | 설명 |
|-----------|---------|------|
| **차이 없음** | ✅ Success | PyPI와 GitHub 결과가 동일 (Failure가 아님) |
| **차이 있음** | ❌ Failure | 달라진 값을 로그·Artifact로 출력해 확인 |

실행 시각·분석 경로처럼 매번 달라지는 값은 비교에서 제외합니다.  
그 외(버전 정보, SRC/BIN/DEP 내용 등)에 차이가 있으면 Failure입니다.

전체 처리 흐름은 [docs/flowchart.md](docs/flowchart.md)를 참고하세요.

## 비교에 사용하는 패키지

### PyPI (기준선)

```bash
pip install fosslight_scanner
```

의존 패키지(source / dependency / binary / util 등)는 PyPI에 배포된 버전이 함께 설치됩니다.

### GitHub (검증 대상)

아래 저장소의 최신 `main` 코드를 설치합니다.

- [fosslight_util](https://github.com/fosslight/fosslight_util)
- [fosslight_source_scanner](https://github.com/fosslight/fosslight_source_scanner)
- [fosslight_dependency_scanner](https://github.com/fosslight/fosslight_dependency_scanner)
- [fosslight_binary_scanner](https://github.com/fosslight/fosslight_binary_scanner)
- [fosslight_scanner](https://github.com/fosslight/fosslight_scanner)
- [fosslight_android_scanner](https://github.com/fosslight/fosslight_android_scanner)
- [fosslight_yocto_scanner](https://github.com/fosslight/fosslight_yocto_scanner)

## 테스트 절차 요약

1. **PyPI venv** 생성 → `fosslight_scanner` 설치 → 예제 저장소 스캔 → Excel 저장  
2. **GitHub venv** 생성 → 위 GitHub 패키지 설치 → 동일 명령으로 스캔 → Excel 저장  
3. Excel 비교
   - 셀/행 단위: `scripts/compare_excel.py`
   - BOM 단위: `fosslight compare`
4. 비교 결과를 로그·JSON으로 출력
   - 차이 없음 → 종료 코드 `0` (Success)
   - 차이 있음 → 종료 코드 `1` (Failure) + 달라진 값 출력

비교 시 매 실행마다 달라지는 **Running time**, **Analyzed path** 는 제외합니다.

## 스케줄 (GitHub Actions)

워크플로: [`.github/workflows/daily_scanner_test.yml`](.github/workflows/daily_scanner_test.yml)

| 시각 (KST) | cron |
|------------|------|
| 09:00 | `0 9 * * *` |
| 11:00 | `0 11 * * *` |
| 16:00 | `0 16 * * *` |

타임존: `Asia/Seoul`  
수동 실행: Actions → **Daily FOSSLight Scanner Test** → **Run workflow**

## 로컬 실행

Python 3.10+ 가 필요합니다.

```bash
chmod +x scripts/run_daily_test.sh
./scripts/run_daily_test.sh
```

결과는 `results/<timestamp>/` 아래에 저장됩니다.

| 파일 | 설명 |
|------|------|
| `FOSSLight-Report_pypi.xlsx` | PyPI 설치본 스캔 결과 |
| `FOSSLight-Report_github.xlsx` | GitHub 설치본 스캔 결과 |
| `excel_diff.txt` / `excel_diff.json` | 셀 단위 비교 결과 |
| `fosslight_compare/` | `fosslight compare` BOM 비교 결과 |

Excel만 따로 비교하려면:

```bash
python3 scripts/compare_excel.py path/to/pypi.xlsx path/to/github.xlsx -o diff.json
```

## 디렉터리 구조

```text
fosslight_scanner_test/
├── .github/workflows/     # 일일 스케줄 CI
├── docs/                  # 문서·플로우차트
├── scripts/
│   ├── run_daily_test.sh  # 설치 → 스캔 → 비교 오케스트레이션
│   └── compare_excel.py   # Excel 셀/행 비교
├── README.md
└── LICENSE
```

## License

Apache-2.0
