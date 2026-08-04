# FOSSLight Scanner Test — Flowchart

이 문서는 PyPI 설치본과 GitHub 설치본의 스캔 결과를 비교하는 전체 흐름을 설명합니다.

## Overview

```mermaid
flowchart TD
    Start([시작<br/>비교: 09:00/11:00/16:00 KST<br/>build: 00:30 KST<br/>또는 workflow_dispatch]) --> Split

    Split[별도 GitHub Actions workflow]

    Split --> T1
    Split --> T2
    Split --> T3

    subgraph T1["Workflow: Daily fosslight_scanner Test"]
        direction TB
        S1["PyPI: pip install fosslight_scanner"]
        S2["GitHub: scanner + util/source/…"]
        S3["fosslight -w LGE-OSS/example"]
        S4["시트/셀 Excel 비교<br/>Scanner Info 제외"]
        S1 --> S3
        S2 --> S3
        S3 --> S4
        S4 --> SR{차이?}
        SR -->|없음| SPass([✅ scanner Success])
        SR -->|있음| SFail([❌ scanner Failure])
    end

    subgraph T2["Workflow: Daily fosslight_yocto Test"]
        direction TB
        Y0[sparse checkout test_files]
        Y1["PyPI: pip install fosslight_yocto"]
        Y2["GitHub: util/source/dependency/binary<br/>scanner/android/yocto (scanner와 동일)"]
        Y3["fosslight_yocto -ip -i -b -p -y -o"]
        Y4["시트/셀 Excel 비교<br/>Scanner Info 제외"]
        Y0 --> Y1
        Y0 --> Y2
        Y1 --> Y3
        Y2 --> Y3
        Y3 --> Y4
        Y4 --> YR{차이?}
        YR -->|없음| YPass([✅ yocto Success])
        YR -->|있음| YFail([❌ yocto Failure])
    end

    subgraph T3["Workflow: Daily fosslight_scanner Build"]
        direction TB
        B1["Checkout fosslight/fosslight_scanner main"]
        B2["pip install . + tox"]
        B3["fosslight_scanner -p LGE-OSS/example"]
        B4["tox -e test_run<br/>Python 3.10–3.14"]
        B1 --> B2 --> B3 --> B4
        B4 --> BPass([✅ build Success])
    end

    style Start fill:#e8f4fc,stroke:#4a90c8
    style SPass fill:#e6f6e6,stroke:#3a9a3a
    style YPass fill:#e6f6e6,stroke:#3a9a3a
    style BPass fill:#e6f6e6,stroke:#3a9a3a
    style SFail fill:#fde8e8,stroke:#c84a4a
    style YFail fill:#fde8e8,stroke:#c84a4a
    style T1 fill:#f7f9fc,stroke:#8aa0b8
    style T2 fill:#f7f9fc,stroke:#8aa0b8
    style T3 fill:#f7f9fc,stroke:#8aa0b8
```

> **판정 기준**
> - **차이 없음** → 해당 workflow Success
> - **차이 있음** → 해당 workflow Failure + 시트/셀 표 출력
> - scanner / yocto / scanner-build workflow는 **독립** 실행·판정

## Detail — fosslight_yocto

```mermaid
flowchart TD
    Fetch[fosslight_yocto_scanner<br/>test_files sparse checkout] --> PyPI
    Fetch --> GitHub

    subgraph PyPI["PyPI"]
        P1["pip install fosslight_yocto"]
        P2["fosslight_yocto -ip … -i … -b … -p … -y … -o test_result"]
        P3[fosslight_report_yocto_pypi.xlsx]
        P1 --> P2 --> P3
    end

    subgraph GitHub["GitHub"]
        G1["pip install GIT_PACKAGES<br/>(util/source/dependency/binary/scanner/android/yocto)"]
        G2["동일 fosslight_yocto 명령"]
        G3[fosslight_report_yocto_github.xlsx]
        G1 --> G2 --> G3
    end

    P3 --> Cmp[compare_excel.py<br/>시트/셀 비교]
    G3 --> Cmp
    Cmp --> Out{차이?}
    Out -->|없음| OK([✅ Success])
    Out -->|있음| NG([❌ Failure + 표 출력])

    style OK fill:#e6f6e6,stroke:#3a9a3a
    style NG fill:#fde8e8,stroke:#c84a4a
```

## Detail — 비교 판정 (시트/셀)

```mermaid
flowchart LR
    Excel[양쪽 FOSSLight Report Excel] --> Filter["Scanner Info 제외"]
    Filter --> Sheets[SRC / BIN / DEP 등 시트별]
    Sheets --> Align[경로 / Package URL 기준 행 정렬]
    Align --> Cell["셀 값 비교<br/>ID·TLSH 제외<br/>License·Depends On 정렬"]
    Cell --> Table["Markdown 표 출력"]
    Table --> Out{차이?}
    Out -->|없음| OK["✅ Success<br/>exit 0"]
    Out -->|있음| NG["❌ Failure<br/>exit 1"]

    style OK fill:#e6f6e6,stroke:#3a9a3a
    style NG fill:#fde8e8,stroke:#c84a4a
```

표 컬럼: `# | Sheet | Type | Key | Column | PyPI | GitHub`

## Related files

| Path | Role |
|------|------|
| [`scripts/compare_excel.py`](../scripts/compare_excel.py) | 시트/셀 단위 비교 → Markdown 표 |
| [`scripts/run_scanner_test.sh`](../scripts/run_scanner_test.sh) | fosslight_scanner 비교 |
| [`scripts/run_yocto_test.sh`](../scripts/run_yocto_test.sh) | fosslight_yocto 비교 |
| [`scripts/run_daily_test.sh`](../scripts/run_daily_test.sh) | 로컬에서 둘 다 실행(선택) |
| [`scripts/common.sh`](../scripts/common.sh) | 공통 헬퍼 |
| [`.github/workflows/daily_scanner_test.yml`](../.github/workflows/daily_scanner_test.yml) | scanner 비교 CI |
| [`.github/workflows/daily_yocto_test.yml`](../.github/workflows/daily_yocto_test.yml) | yocto 비교 CI |
| [`.github/workflows/daily_scanner_build.yml`](../.github/workflows/daily_scanner_build.yml) | scanner main daily build + tox |
