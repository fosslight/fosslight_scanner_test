# FOSSLight Scanner Test — Flowchart

이 문서는 PyPI 설치본과 GitHub 설치본의 스캔 결과를 비교하는 전체 흐름을 설명합니다.

## Overview

```mermaid
flowchart TD
    Start([시작<br/>Schedule 09:00 / 11:00 / 16:00 KST<br/>또는 workflow_dispatch]) --> Split

    Split[별도 GitHub Actions workflow]

    Split --> T1
    Split --> T2

    subgraph T1["Workflow: Daily fosslight_scanner Test"]
        direction TB
        S1["PyPI: pip install fosslight_scanner"]
        S2["GitHub: scanner + util/source/…"]
        S3["fosslight -w LGE-OSS/example"]
        S4[Excel 비교]
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
        Y4[Excel 비교]
        Y0 --> Y1
        Y0 --> Y2
        Y1 --> Y3
        Y2 --> Y3
        Y3 --> Y4
        Y4 --> YR{차이?}
        YR -->|없음| YPass([✅ yocto Success])
        YR -->|있음| YFail([❌ yocto Failure])
    end

    style Start fill:#e8f4fc,stroke:#4a90c8
    style SPass fill:#e6f6e6,stroke:#3a9a3a
    style YPass fill:#e6f6e6,stroke:#3a9a3a
    style SFail fill:#fde8e8,stroke:#c84a4a
    style YFail fill:#fde8e8,stroke:#c84a4a
    style T1 fill:#f7f9fc,stroke:#8aa0b8
    style T2 fill:#f7f9fc,stroke:#8aa0b8
```

> **판정 기준**
> - **차이 없음** → 해당 workflow Success
> - **차이 있음** → 해당 workflow Failure + diff 출력
> - scanner / yocto workflow는 **독립** 실행·판정

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

    P3 --> Cmp[compare_excel.py]
    G3 --> Cmp
    Cmp --> Out{차이?}
    Out -->|없음| OK([✅ Success])
    Out -->|있음| NG([❌ Failure + diff 출력])

    style OK fill:#e6f6e6,stroke:#3a9a3a
    style NG fill:#fde8e8,stroke:#c84a4a
```

## Detail — 비교 판정

```mermaid
flowchart LR
    Excel[양쪽 FOSSLight Report Excel] --> Sheets{시트별 비교}

    Sheets --> Info[Scanner Info]
    Sheets --> Data[SRC / BIN / DEP 등]

    Info --> Ignore["무시: Running time,<br/>Analyzed path<br/>실행마다 달라짐"]
    Info --> Check["검사: Tool information,<br/>Comment, Python version 등"]

    Data --> Align[경로 / Package URL 기준<br/>행 정렬]
    Align --> Cell[셀 값 비교<br/>ID, TLSH 제외]

    Check --> Diff[차이 목록 출력]
    Cell --> Diff

    Diff --> Out{차이 개수}
    Out -->|0 차이 없음| OK["✅ Success<br/>exit 0"]
    Out -->|≥1 차이 있음| NG["❌ Failure<br/>exit 1<br/>diff 출력으로 확인"]

    style Ignore fill:#f0f0f0,stroke:#999
    style OK fill:#e6f6e6,stroke:#3a9a3a
    style NG fill:#fde8e8,stroke:#c84a4a
```

## Related files

| Path | Role |
|------|------|
| [`scripts/run_scanner_test.sh`](../scripts/run_scanner_test.sh) | fosslight_scanner 비교 |
| [`scripts/run_yocto_test.sh`](../scripts/run_yocto_test.sh) | fosslight_yocto 비교 |
| [`scripts/run_daily_test.sh`](../scripts/run_daily_test.sh) | 로컬에서 둘 다 실행(선택) |
| [`scripts/compare_excel.py`](../scripts/compare_excel.py) | Excel 셀/행 비교 |
| [`scripts/common.sh`](../scripts/common.sh) | 공통 헬퍼 |
| [`.github/workflows/daily_scanner_test.yml`](../.github/workflows/daily_scanner_test.yml) | scanner CI |
| [`.github/workflows/daily_yocto_test.yml`](../.github/workflows/daily_yocto_test.yml) | yocto CI |
