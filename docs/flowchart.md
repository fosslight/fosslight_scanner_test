# FOSSLight Scanner Test — Flowchart

이 문서는 PyPI 설치본과 GitHub 설치본의 스캔 결과를 비교하는 전체 흐름을 설명합니다.

## Overview

```mermaid
flowchart TD
    Start([시작<br/>Schedule 09:00 / 11:00 / 16:00 KST<br/>또는 workflow_dispatch]) --> Setup[Checkout + Python 3.12 준비]

    Setup --> Parallel{두 환경에서<br/>동일 스캔 수행}

    Parallel --> PyPI
    Parallel --> GitHub

    subgraph PyPI["① PyPI 기준선"]
        direction TB
        P1[venv_pypi 생성]
        P2["pip install fosslight_scanner"]
        P3["fosslight -w https://github.com/LGE-OSS/example"]
        P4[FOSSLight-Report_pypi.xlsx]
        P1 --> P2 --> P3 --> P4
    end

    subgraph GitHub["② GitHub 검증 대상"]
        direction TB
        G1[venv_git 생성]
        G2[GitHub main 패키지 설치]
        G2a["util / source / dependency<br/>binary / scanner<br/>android / yocto"]
        G3["fosslight -w https://github.com/LGE-OSS/example"]
        G4[FOSSLight-Report_github.xlsx]
        G1 --> G2 --> G2a --> G3 --> G4
    end

    P4 --> Compare
    G4 --> Compare

    subgraph Compare["③ 결과 비교"]
        direction TB
        C1[compare_excel.py<br/>셀 / 행 단위 비교]
        C2[fosslight compare<br/>BOM 단위 비교]
        C3[excel_diff.txt / .json 출력]
        C1 --> C3
        C2 --> C3
    end

    Compare --> Decision{Excel 결과<br/>차이 있음?}

    Decision -->|차이 없음| Pass([✅ Success / exit 0<br/>PyPI와 GitHub 결과 동일])
    Decision -->|차이 있음| Fail([❌ Failure / exit 1<br/>차이 내용 출력 + Artifact])

    style Start fill:#e8f4fc,stroke:#4a90c8
    style Pass fill:#e6f6e6,stroke:#3a9a3a
    style Fail fill:#fde8e8,stroke:#c84a4a
    style PyPI fill:#f7f9fc,stroke:#8aa0b8
    style GitHub fill:#f7f9fc,stroke:#8aa0b8
    style Compare fill:#fff8e8,stroke:#c9a227
```

> **판정 기준**
> - **차이 없음** → Success (Failure가 아님)
> - **차이 있음** → Failure이며, 달라진 값을 로그/`excel_diff`로 출력해 확인 가능

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

## Sequence

```mermaid
sequenceDiagram
    autonumber
    participant GA as GitHub Actions
    participant Py as venv_pypi
    participant Gh as venv_git
    participant Ex as LGE-OSS/example
    participant Cmp as compare_excel.py

    GA->>Py: create venv + pip install fosslight_scanner
    Py->>Ex: fosslight -w (clone & analyze)
    Ex-->>Py: FOSSLight-Report_pypi.xlsx

    GA->>Gh: create venv + pip install git+https://...
    Gh->>Ex: fosslight -w (clone & analyze)
    Ex-->>Gh: FOSSLight-Report_github.xlsx

    GA->>Cmp: compare pypi.xlsx vs github.xlsx
    Cmp-->>GA: excel_diff + exit code
    GA->>GA: fosslight compare (BOM)
    GA->>GA: Upload artifacts / Job Summary
```

## Related files

| Path | Role |
|------|------|
| [`scripts/run_daily_test.sh`](../scripts/run_daily_test.sh) | 설치 · 스캔 · 비교 오케스트레이션 |
| [`scripts/compare_excel.py`](../scripts/compare_excel.py) | Excel 셀/행 비교 |
| [`.github/workflows/daily_scanner_test.yml`](../.github/workflows/daily_scanner_test.yml) | 스케줄 / 수동 실행 CI |
