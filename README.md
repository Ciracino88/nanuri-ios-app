# 나누리 회계

<p align="center">
  <img width="324" height="680" alt="nanuri-ios-app" src="https://github.com/user-attachments/assets/5104a724-4f7d-4d54-bebd-5da0a69db321" />
</p>


## 배경

교회 청년부 계좌는 인터넷 뱅킹을 만들지 않았기 때문에, 현금 인출/송금 작업을 하기 위해 농협 ATM 기기를 매번 찾아가야 하는 번거로움이 있었다. 농협 ATM에 대한 의존도가 높고, 이로 인해 작업 처리가 지연된다는 문제점을 해결하기 위해, 송금 처리를 담당할 중간 플랫폼을 만들고자 한다.

## 해결 방안

- 중간 플랫폼으로 토스뱅크 모임통장을 두고, 여기서 송금 및 입금을 처리한다.
- 송금 요청 폼을 작성할 수 있는 웹페이지를 두고, 요청을 보내면 나누리 회계 앱으로 푸시 알림을 쏜다.
- 나누리 회계 앱에서 요청을 확인하고, 적절한 요청일 시, 토스 딥링크를 통해 송금 작업을 진행한다.

## 왜 토스뱅크인가

- 어떤 은행권이든 입출금이 가능하며, 수수료가 발생하지 않는다.
- 송금 처리가 간편하고 빠르다.
- 거래내역서 내보내기 기능을 제공하기에 결산 시, 데이터 전산화에 유리하다.

## 기술 스택

| 영역 | 기술 |
|---|---|
| 청구 내역 저장 | Supabase (PostgreSQL) |
| 청구 내역 작성/제출, 영수증 이미지 저장 | Cloudflare Worker / R2 |
| 청구 내역 확인 | Swift (iOS) |
| 실제 송금 작업 수행 | Toss App (딥링크) |

## 아키텍처 다이어그램

```mermaid
flowchart TD
    subgraph 청년부["청년부 (인터넷뱅킹 미보유)"]
        A[청구자] -->|청구 내역 작성 후 제출| B["Cloudflare Worker/Pages\n(청구 요청 웹 폼)"]
    end

    subgraph 요청처리["요청 처리 계층"]
        B -->|청구 내역 + 영수증 이미지 저장| D[(Supabase\nPostgreSQL + Storage)]
        D -->|영수증 URL 저장| R[Cloudflare R2]
        B -->|Push Notification 발송| E
    end

    subgraph 나누리["나누리 회계 앱 (Swift/iOS)"]
        E[담당자 알림 수신] --> F{요청 내용\n적절성 확인}
        F -->|승인| G[토스 딥링크 실행]
        F -->|반려| H[요청 반려/보류]
        M[담당자] -->|청구 내역 조회| D
    end

    subgraph 송금["실제 송금 계층"]
        G --> I[토스 앱\nToss App]
        I -->|송금 실행| J[(토스뱅크 모임통장)]
        J -->|입출금 처리\n수수료 없음| K[대상 계좌\n은행 무관]
    end

    subgraph 결산["결산"]
        J -->|거래내역서 내보내기| L[전산화된 결산 데이터]
        M -->|청구 내역과 대조| L
    end

    style D fill:#3ECF8E,color:#000
    style R fill:#F38020,color:#fff
    style I fill:#0064FF,color:#fff
    style J fill:#0064FF,color:#fff
```

## 핵심 흐름 요약

1. 청구자가 웹 폼(React/Tailwind, Cloudflare Pages)에서 송금 요청 → Worker가 Supabase에 저장 + R2에 영수증 저장
2. Supabase 저장과 동시에 나누리 앱(Swift)으로 Push 알림
3. 담당자가 앱에서 요청 확인 후 승인하면 토스 딥링크로 토스 앱 실행
4. 토스뱅크 모임통장에서 실제 송금/입금 처리 (은행 무관, 무수수료)
5. 결산 시 토스 거래내역서 + Supabase 청구 데이터를 대조해 전산화
