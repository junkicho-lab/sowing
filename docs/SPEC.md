# 교사 일상 기록 앱 기술 명세서

**프로젝트 코드네임**: `Sowing` (씨앗 뿌리기)
**문서 버전**: v0.1 (Draft)
**문서 대상**: Ruby 백엔드/풀스택 엔지니어
**작성 목적**: 옵시디언 학습 통합 교사 일상 기록 데스크톱 앱의 설계·구현 기준 제공

---

## 0. 문서 사용 가이드

본 문서는 단일 엔지니어 또는 소규모 팀이 MVP를 8~12주 내 출시할 수 있도록 설계되었다. 다음 순서로 읽기를 권장한다.

1. §1~§3: 제품 컨텍스트와 핵심 개념 모델 — **반드시 먼저 읽을 것**. 본 앱의 모든 기술 결정은 §3의 개념 모델에서 파생된다.
2. §6~§9: 기술 스택과 데이터 아키텍처
3. §10~§12: 구현 가이드
4. §13 이후: 운영·확장·리스크

---

## 1. 프로젝트 개요

### 1.1 배경

대한민국 현직 교사 다수는 일상에서 의미 있는 사건·통찰·반성을 끊임없이 마주하지만, 이를 **체계적으로 기록·축적·재활용**하는 시스템을 갖추지 못한 경우가 많다. 옵시디언(Obsidian)은 교사의 평생 학습 자산을 구축하기에 이상적인 도구이지만, 다음의 진입 장벽이 존재한다.

- 마크다운 문법 학습 부담
- 빈 볼트(empty vault) 앞에서 무엇부터 적어야 할지 모르는 막막함
- 폴더 구조·태그 체계·링크 활용을 동시에 학습해야 하는 인지 부하
- 매일 꾸준히 기록하는 **습관 형성** 자체의 어려움

### 1.2 비전

**"옵시디언을 배우려고 앱을 켜는 것이 아니라, 앱을 매일 쓰다 보면 옵시디언을 쓰고 있게 만든다."**

본 앱은 옵시디언 학습 튜토리얼이 아니다. 본 앱은 **옵시디언 호환 마크다운 파일을 생성하는, 교사용 일상 기록 도구**이다. 사용자가 앱을 통해 작성한 모든 데이터는 처음부터 옵시디언 볼트 구조로 저장되며, 사용자가 옵시디언 앱을 설치한 순간 동일한 데이터를 그대로 열 수 있다. 즉 본 앱은 **옵시디언으로 가는 다리(bridge)**다.

### 1.3 목표 (Goals)

| # | 목표 | 측정 지표 |
|---|------|-----------|
| G1 | 옵시디언 사전 지식 0인 교사가 30분 내 첫 기록 작성 완료 | 신규 사용자 첫 기록까지 평균 시간 ≤ 30분 |
| G2 | 매일 1회 이상 기록하는 습관 형성 지원 | D30 리텐션 ≥ 40%, 평균 주간 기록 횟수 ≥ 5회 |
| G3 | 모든 데이터를 옵시디언 호환 마크다운으로 로컬 저장 | 데이터 100%가 표준 마크다운 + YAML frontmatter 형식 |
| G4 | 완전 오프라인·로컬 우선 동작 보장 | 네트워크 차단 환경에서 모든 핵심 기능 정상 동작 |
| G5 | 교사 도메인에 특화된 기록 템플릿 제공 | 출시 시점 템플릿 ≥ 12종 (수업 성찰/학생 관찰/회의록 등) |

### 1.4 비목표 (Non-Goals)

- ❌ 옵시디언의 기능을 모두 재구현하지 않는다 (그래프 뷰·플러그인 시스템·캔버스 등 제외)
- ❌ 클라우드 동기화 서버를 직접 운영하지 않는다 (사용자가 별도로 iCloud/Dropbox/Syncthing 등 사용)
- ❌ 협업·공유·실시간 편집 기능은 MVP 범위 외
- ❌ 모바일 앱은 본 명세서 범위 외 (향후 확장)
- ❌ AI 기반 자동 작성·요약은 MVP 범위 외 (Phase 3 이후)

---

## 2. 타겟 사용자 및 페르소나

### 2.1 주 사용자 정의

- **직군**: 초·중·고 현직 교사 (관리직 포함)
- **기술 수준**: 일반적인 PC 사용자. 마크다운·Git·CLI에 익숙하지 않음
- **OS**: Windows 10/11 (60%), macOS (35%), Linux (5%) 추정
- **사전 지식**: 옵시디언 사용 경험 없음을 기본 가정

### 2.2 핵심 페르소나

**페르소나 A — 신임 교사 민지 (28세, 초등 4년차)**
- 학급 운영 노하우를 쌓고 싶지만 매일 일지를 적으려다 3일 만에 포기한 경험 다수
- 노션·에버노트를 시도했으나 부담을 느끼고 결국 손글씨 메모지로 회귀
- 핵심 니즈: **부담 없는 진입**, **꾸준함을 도와주는 장치**

**페르소나 B — 중견 교사 수진 (45세, 중학교 부장)**
- 30년 가까운 경력을 정리·전수하고 싶음
- 이미 워드·한글 파일이 산재해 있음
- 핵심 니즈: **기록의 구조화**, **장기 보존성**, **검색·재활용**

본 앱은 페르소나 A를 1차 타깃으로 설계하되, B의 니즈도 데이터 구조 설계에서 충족하도록 한다.

---

## 3. 핵심 개념 모델

본 §3은 **본 앱의 모든 기능 분류·UI 구조·데이터 모델의 근간**이다. 엔지니어는 본 절을 충분히 이해한 뒤 구현에 착수해야 한다.

### 3.1 메모 / 필기 / 기록 3단계 프레임워크

본 앱은 "기록"을 단일 행위로 보지 않고, 인지적 깊이가 다른 세 가지 모드로 구분한다.

| 모드 | 정의 | 특징 | 옵시디언 매핑 |
|------|------|------|---------------|
| **메모 (Memo)** | 휘발성 즉시 포착. 떠오른 생각·관찰을 1~2문장으로 던져두는 행위 | 짧음, 빠름, 분류 불필요, 초안 상태 | `00_Inbox/` 폴더의 timestamp 파일 |
| **필기 (Note)** | 외부 자료를 정리·요약하는 학습 행위. 책·연수·회의 내용을 자기 언어로 다시 쓰는 것 | 구조화됨, 분류·태그 있음, 출처 명시 | `20_Notes/{카테고리}/` 하위 |
| **기록 (Record)** | 자기 경험·통찰의 영구 보관용 깊이 있는 글. 미래의 나·타인에게 전달할 수 있는 형태 | 완결성, 성찰적, 링크와 맥락 풍부 | `30_Records/{연도}/` 하위 |

**설계 원칙**: 사용자는 모드 전환 비용이 없어야 한다. 메모로 시작한 글이 필기로, 다시 기록으로 **승격(promote)**될 수 있어야 한다. 이는 옵시디언 사용자들이 흔히 사용하는 "Fleeting → Literature → Permanent" (Zettelkasten) 흐름과 본질적으로 동일하지만, 한국 교사의 언어 감각에 맞게 재명명되었다.

### 3.2 씨앗에서 숲으로 (Seed to Forest) 성장 모델

기록의 양적 축적이 질적 변화를 만든다는 본 앱의 철학을 사용자 인터페이스에 구현한다.

```
씨앗(Seed) → 새싹(Sprout) → 나무(Tree) → 숲(Forest)
   메모 1개   메모 누적     필기·기록 연결    지식 네트워크
```

각 단계는 **사용자 대시보드의 시각화**로 표현되며, 단순한 게이미피케이션이 아니라 **자신의 기록 자산이 자라는 모습을 실감하게 만드는 장치**다.

### 3.3 옵시디언 호환성 원칙 (Obsidian-Compatible Principle)

본 앱의 가장 중요한 기술 원칙이다.

> **본 앱이 생성하는 모든 파일은, 본 앱이 사라져도 옵시디언으로 정상적으로 열고 편집할 수 있어야 한다.**

이를 위한 구체적 규칙:

1. **모든 콘텐츠는 마크다운 파일(.md)로 저장**한다. 독자적 바이너리 포맷 금지.
2. **메타데이터는 YAML frontmatter**에 저장한다. (옵시디언 native 지원)
3. **파일 간 관계는 `[[위키링크]]`** 로 표현한다. (옵시디언 native 문법)
4. **이미지·첨부는 볼트 내 `assets/` 폴더**에 저장하고 상대 경로로 참조한다.
5. SQLite DB는 **인덱스·캐시·앱 상태** 저장용으로만 쓴다. **콘텐츠는 절대 DB에만 두지 않는다**.

이 원칙의 함의: 사용자의 데이터는 항상 **마크다운 파일이 단일 진실 원천(Single Source of Truth)**이다. SQLite가 깨져도 마크다운에서 재구축 가능해야 한다.

---

## 4. 기능 요구사항

### 4.1 MVP 범위 (Phase 1, 출시 필수)

#### F1. 첫 실행 온보딩
- F1.1 볼트 위치 선택/생성 마법사 (기본값: `~/Documents/SowingVault/`)
- F1.2 기존 옵시디언 볼트 사용 옵션 (디렉토리 검증 후 추가 모드 진입)
- F1.3 사용자 프로필 입력 (이름, 학교급, 담당 교과/학년 — 모두 선택)
- F1.4 첫 메모 작성 튜토리얼 (3분 인터랙티브)

#### F2. 메모 (Memo) 기능
- F2.1 글로벌 단축키(`Ctrl+Shift+M` / `Cmd+Shift+M`)로 어디서든 메모 창 호출
- F2.2 단일 입력창 + 저장 버튼만 있는 미니멀 UI
- F2.3 자동 timestamp 파일명: `YYYY-MM-DD_HHmmss.md`
- F2.4 자동 frontmatter 부여 (mode, created_at, tags 등)
- F2.5 저장 직후 창 자동 닫힘 (방해 최소화)

#### F3. 필기 (Note) 기능
- F3.1 카테고리 선택 후 작성 (수업/연수/도서/회의 등)
- F3.2 출처 필드 필수 (책 제목·연수명·회의일자 등)
- F3.3 마크다운 에디터 with 실시간 프리뷰
- F3.4 템플릿 적용 가능 (§4.4 참조)

#### F4. 기록 (Record) 기능
- F4.1 카테고리 + 제목 + 본문 + 태그 입력
- F4.2 마크다운 에디터 (with 위키링크 자동완성)
- F4.3 `[[` 입력 시 기존 파일 검색 팝업
- F4.4 다른 기록·필기·메모 링크 가능

#### F5. 승격(Promote) 기능
- F5.1 메모 → 필기 승격: 카테고리·출처 추가 후 `20_Notes/`로 이동
- F5.2 필기·메모 → 기록 승격: 제목·태그 보강 후 `30_Records/{연도}/`로 이동
- F5.3 승격 시 원본 frontmatter의 `promoted_from` 필드에 원본 경로 기록 (감사 추적)
- F5.4 승격은 파일 이동 + frontmatter 업데이트 + 인덱스 갱신의 트랜잭션

#### F6. 검색 및 탐색
- F6.1 전문 검색(full-text search) — SQLite FTS5 기반
- F6.2 태그·카테고리 필터
- F6.3 날짜 범위 필터
- F6.4 최근 작성 목록 (대시보드)

#### F7. 대시보드 (씨앗-숲 시각화)
- F7.1 오늘/이번 주/이번 달 기록 수
- F7.2 연속 작성일(streak) 카운터
- F7.3 메모/필기/기록 비율 시각화
- F7.4 누적 기록 자산 그래프 (씨앗→숲 메타포)

#### F8. 교사 특화 템플릿
- 출시 시점 12종 템플릿 제공:
  1. 수업 성찰 (Lesson Reflection)
  2. 학생 관찰 일지 (Student Observation)
  3. 학부모 상담 기록 (Parent Counseling)
  4. 회의록 (Meeting Notes)
  5. 연수 메모 (Training Notes)
  6. 도서 독서록 (Book Notes)
  7. 학급 운영 일지 (Classroom Journal)
  8. 동료 수업 참관 (Peer Observation)
  9. 평가 분석 (Assessment Analysis)
  10. 진로 상담 기록 (Career Counseling)
  11. 학교 행사 기록 (School Event)
  12. 자유 일기 (Free Journal)

#### F9. 옵시디언 볼트 동기화 보장
- F9.1 외부 변경 감지 (파일시스템 watcher)
- F9.2 외부 편집된 파일 인덱스 자동 갱신
- F9.3 충돌 감지 시 사용자 확인 다이얼로그

### 4.2 Phase 2 범위 (출시 후 3개월 내)

- 일일/주간 회고 알림 (시스템 트레이 연동)
- 한 줄 일기 위젯 (오늘의 마음 한 줄)
- PDF/이미지 첨부 OCR (이미지에서 텍스트 추출)
- 백업/복원 (zip 아카이브)
- 다크 모드
- 통계 대시보드 강화 (월/년 단위 회고)

### 4.3 Phase 3 범위 (장기)

- 로컬 LLM 연동 (Ollama 등) 기반 자동 태그 제안
- 음성 메모 → 텍스트 변환 (음성 입력)
- 모바일 앱 (Flutter 등 별도 구현)
- 협업 모드 (옵션, 동료 교사와 선택적 공유)

### 4.4 템플릿 시스템

템플릿은 마크다운 파일로 `templates/` 디렉토리에 저장된다. 사용자가 직접 추가·수정 가능.

```yaml
---
template_id: lesson_reflection
template_name: 수업 성찰
template_version: 1
applicable_modes: [note, record]
icon: 📚
---

# {{ title }}

**일시**: {{ date }} {{ time }}
**대상**: {{ class }}
**단원**: {{ unit }}

## 오늘 수업의 핵심
{{ cursor }}

## 잘 된 점

## 아쉬운 점

## 다음 수업에 적용할 것

#수업성찰 #{{ subject }}
```

`{{ }}` 플레이스홀더는 Liquid 또는 ERB 기반 단순 치환으로 처리한다.

---

## 5. 비기능 요구사항

### 5.1 성능 (Performance)

| 지표 | 목표 |
|------|------|
| 앱 콜드 스타트 | < 3초 (10,000건 이하 볼트 기준) |
| 메모 글로벌 단축키 응답 | < 200ms (입력 창 표시까지) |
| 검색 응답 (10,000건 기준) | < 500ms |
| 파일 저장 → 디스크 fsync | < 100ms |

### 5.2 보안 및 프라이버시

- **로컬 우선(local-first)**. 외부 네트워크 통신은 업데이트 확인 외 일체 없음. 옵션으로 완전 차단 가능.
- 사용자 데이터는 사용자 디렉토리 내 평문 마크다운으로 저장. **암호화는 OS 레벨(FileVault, BitLocker)에 위임**.
- 텔레메트리·사용 통계 수집 안 함. 크래시 리포트도 옵트인.
- 업데이트 확인은 서명 검증된 GitHub Releases만 사용.

### 5.3 접근성 (Accessibility)

- 키보드 네비게이션 100% 지원 (마우스 없이 모든 기능 사용 가능)
- 폰트 크기 4단계 조절
- 고대비 테마 제공
- 스크린리더 호환성 (Windows Narrator, macOS VoiceOver 기본 지원)

### 5.4 다국어

- MVP: 한국어 (단일 언어)
- i18n 구조는 처음부터 설계 (gettext 또는 r18n)
- Phase 2에서 영어 추가 검토

### 5.5 호환성

- Windows 10 (1809+) / 11
- macOS 11 (Big Sur)+
- Linux: Ubuntu 22.04+ / Fedora 38+

---

## 6. 기술 스택

### 6.1 핵심 결정과 근거

| 영역 | 선택 | 대안 | 선택 이유 |
|------|------|------|-----------|
| 언어 | **Ruby 3.3+** | Python, Rust | 명세 요구사항. Ruby의 표현력과 DSL 친화성이 템플릿/규칙 기반 시스템에 적합 |
| 앱 형태 | **로컬 웹 서버 + 브라우저 UI** (권장) | 네이티브 GUI (Glimmer DSL), Tauri+Ruby | 단일 코드베이스로 크로스플랫폼, 모던 UI 구현 용이, 추후 모바일 확장에 유리 |
| 웹 프레임워크 | **Sinatra 4.x** | Rails, Roda | 가벼움, 단일 파일에서 시작 가능, 학습 곡선 낮음 |
| 프론트엔드 | **Hotwire (Turbo + Stimulus)** | React, Vue | Ruby 생태계 정합성, 빌드 도구 최소화, 서버 렌더링 친화적 |
| DB (메타) | **SQLite 3.45+** | DuckDB, JSON 파일 | 단일 파일, 트랜잭션, FTS5 강력함 |
| ORM | **Sequel** | ActiveRecord | 가벼움, 명시적, 마이그레이션 깔끔 |
| 마크다운 파서 | **Commonmarker (CommonMark)** | Kramdown, Redcarpet | GFM 지원, 옵시디언 호환성 우수, libcmark-gfm 기반 빠름 |
| 파일시스템 감시 | **Listen 3.x** | rb-fsevent 직접 | 크로스플랫폼 추상화 |
| 패키징 | **Tebako** | rubyc, Traveling Ruby | 단일 실행 바이너리, 모던 Ruby 지원 |
| 테스트 | **RSpec + Capybara** | Minitest | 본 앱 도메인 표현력 우수 |
| 백그라운드 작업 | **Async (async gem)** | Sidekiq | 외부 Redis 의존성 없이 로컬 처리 |

### 6.2 최종 Gemfile 골격

```ruby
source "https://rubygems.org"
ruby "3.3.0"

# Core
gem "sinatra", "~> 4.0"
gem "puma", "~> 6.4"
gem "rackup", "~> 2.1"

# Data
gem "sequel", "~> 5.80"
gem "sqlite3", "~> 2.0"

# Markdown / Files
gem "commonmarker", "~> 1.1"
gem "front_matter_parser", "~> 1.0"  # YAML frontmatter 처리
gem "listen", "~> 3.9"               # 파일시스템 감시

# View
gem "tilt", "~> 2.4"
gem "erubi", "~> 1.13"

# i18n
gem "r18n-core", "~> 5.0"

# Background
gem "async", "~> 2.10"

# Utilities
gem "dry-validation", "~> 1.10"      # 입력 검증
gem "dry-monads", "~> 1.6"           # Result 타입
gem "zeitwerk", "~> 2.6"             # 자동 로딩

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "capybara", "~> 3.40"
  gem "factory_bot", "~> 6.4"
  gem "rubocop", "~> 1.65"
  gem "standard", "~> 1.41"
end

group :development do
  gem "rerun", "~> 0.14"             # 파일 변경 시 서버 재시작
  gem "pry-byebug"
end

group :production do
  gem "tebako", "~> 0.10"            # 패키징
end
```

### 6.3 GUI 대안: 네이티브 데스크톱 앱이 필요한 경우

만약 브라우저 의존을 피하고 진정한 네이티브 앱을 원한다면, 대안으로 **Glimmer DSL for LibUI**를 사용할 수 있다.

```ruby
# 대안 Gemfile 일부
gem "glimmer-dsl-libui", "~> 0.13"
```

이 경우 §10의 UI 가이드는 LibUI의 컴포넌트 모델로 재해석되어야 한다. 본 명세서의 권장은 **로컬 웹 서버 방식**이다. 모던 UI 구현 자유도와 추후 확장성이 압도적으로 우수하기 때문이다.


---

## 7. 시스템 아키텍처

### 7.1 전체 구성도

```
┌─────────────────────────────────────────────────────────────┐
│                     사용자 (브라우저)                        │
│            http://127.0.0.1:48723 (랜덤 로컬 포트)          │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTP/Turbo
┌────────────────────────────▼────────────────────────────────┐
│                  Sinatra App (Puma)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Controllers │  │   Services   │  │   Helpers    │     │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘     │
│         │                  │                                │
│  ┌──────▼──────────────────▼────────────────────────┐      │
│  │              Domain Layer (Use Cases)            │      │
│  │  CreateMemo, PromoteToNote, SearchEntries 등     │      │
│  └──────┬───────────────────────┬───────────────────┘      │
│         │                       │                          │
│  ┌──────▼─────────┐    ┌────────▼──────────┐              │
│  │   VaultRepo    │    │    IndexRepo      │              │
│  │ (마크다운 파일) │    │   (SQLite FTS5)   │              │
│  └──────┬─────────┘    └────────┬──────────┘              │
└─────────┼───────────────────────┼─────────────────────────┘
          │                       │
   ┌──────▼────────┐     ┌────────▼────────┐
   │ Vault 디렉토리│     │  index.sqlite3  │
   │  (사용자 폴더) │     │  (앱 데이터 폴더) │
   │  *.md 파일들   │     │                 │
   └───────────────┘     └─────────────────┘
          ▲
          │ 외부 변경 감지
   ┌──────┴────────┐
   │ FileWatcher   │
   │  (Listen gem) │
   └───────────────┘
```

### 7.2 계층 책임 분리

| 계층 | 책임 | 의존 방향 |
|------|------|-----------|
| **Controllers** | HTTP 요청 수신, 입력 검증, 응답 렌더링 | → Services |
| **Services (Use Cases)** | 비즈니스 로직, 트랜잭션 경계 | → Repositories, Domain |
| **Domain** | Entry, Memo, Note, Record 등 도메인 객체와 규칙 | (의존 없음) |
| **Repositories** | VaultRepo (파일 I/O), IndexRepo (SQLite) | → Domain, Infrastructure |
| **Infrastructure** | 파일시스템, SQLite 어댑터, FileWatcher | (의존 없음) |

**핵심 원칙**: Domain 계층은 Sinatra·Sequel·파일시스템에 대해 알지 못한다. 이를 통해 도메인 규칙(승격 규칙, 옵시디언 호환성 검증 등)이 단위 테스트로 빠르게 검증 가능하다.

### 7.3 두 저장소(Repository)의 동기화 전략

본 앱의 **가장 까다로운 설계 지점**이다. 마크다운 파일(SoT)과 SQLite 인덱스가 어긋날 가능성을 다뤄야 한다.

**쓰기 흐름 (앱이 변경 주체)**
```
1. VaultRepo.write(entry)       — 마크다운 파일 저장 + fsync
2. IndexRepo.upsert(entry)      — SQLite 인덱스 갱신
3. (실패 시) IndexRepo.mark_dirty(path) — 다음 부팅 시 재인덱싱
```

**외부 변경 흐름 (사용자가 옵시디언/에디터로 직접 수정)**
```
1. FileWatcher가 변경 이벤트 수신 (debounce 500ms)
2. 변경된 파일의 mtime/hash 비교
3. 변경 확인 시 IndexRepo.upsert(parsed_entry)
4. 클라이언트(브라우저)에 SSE/Turbo Stream으로 갱신 푸시
```

**부팅 시 일관성 검증**
- 볼트 디렉토리 스캔 vs SQLite 레코드 비교
- 신규 파일: 인덱스 추가
- 사라진 파일: 인덱스 제거 (옵션: tombstone)
- mtime 변경 파일: 재파싱 후 갱신

---

## 8. 데이터 모델

### 8.1 마크다운 파일 구조 (Single Source of Truth)

모든 콘텐츠 파일은 다음 구조를 따른다.

```markdown
---
id: 01H8Z2X9QK7N3M4P5R6S7T8U9V        # ULID (영구 식별자)
mode: memo                             # memo | note | record
title: 오늘 1교시 수업 메모            # null 허용 (메모는 보통 없음)
category: lesson_reflection            # null 허용
created_at: 2026-05-07T09:23:14+09:00
updated_at: 2026-05-07T09:23:14+09:00
tags: [수업, 1학년, 수학]
template: lesson_reflection            # null 허용
promoted_from: 00_Inbox/2026-05-01_153022.md  # 승격된 경우만
source: null                           # 필기의 경우 책/연수명 등
---

# 본문 시작

마크다운 본문이 여기에 위치합니다.

[[다른 기록 링크 예시]]
```

**필수 frontmatter 필드**: `id`, `mode`, `created_at`, `updated_at`
**선택 frontmatter 필드**: 나머지 모두

`id`는 ULID(Universally Unique Lexicographically Sortable Identifier)를 권장한다. 시간순 정렬 가능 + 충돌 안전 + URL-safe.

### 8.2 디렉토리 구조 (Vault Layout)

```
{VaultRoot}/
├── .sowing/                          # 앱 메타데이터 (옵시디언이 무시)
│   ├── config.yml                    # 사용자 설정
│   └── templates/                    # 사용자 정의 템플릿
├── 00_Inbox/                         # 메모 (휘발성 포착)
│   ├── 2026-05-07_092314.md
│   └── 2026-05-07_153022.md
├── 10_Daily/                         # 일일 기록 (Phase 2)
│   └── 2026/
│       └── 2026-05-07.md
├── 20_Notes/                         # 필기
│   ├── lessons/
│   ├── trainings/
│   ├── books/
│   └── meetings/
├── 30_Records/                       # 기록 (영구)
│   └── 2026/
│       └── 학급운영/
├── assets/                           # 이미지·첨부
│   └── 2026/
│       └── 05/
└── templates/                        # 시스템 제공 템플릿
    ├── lesson_reflection.md
    └── ...
```

폴더명 앞 숫자 prefix는 **옵시디언 사이드바에서 정렬을 보장**하기 위함이다. 사용자가 변경할 수 있다.

### 8.3 SQLite 스키마

`{AppData}/index.sqlite3`에 저장. 콘텐츠 사본은 저장하지 않는다.

```sql
-- 엔트리 메타 인덱스
CREATE TABLE entries (
  id              TEXT PRIMARY KEY,         -- ULID
  path            TEXT NOT NULL UNIQUE,     -- 볼트 상대 경로
  mode            TEXT NOT NULL CHECK(mode IN ('memo','note','record')),
  title           TEXT,
  category        TEXT,
  template        TEXT,
  source          TEXT,
  promoted_from   TEXT,
  created_at      TEXT NOT NULL,            -- ISO 8601
  updated_at      TEXT NOT NULL,
  file_mtime      INTEGER NOT NULL,         -- 동기화 비교용
  file_hash       TEXT NOT NULL,            -- SHA-256 prefix 16
  word_count      INTEGER DEFAULT 0,
  indexed_at      TEXT NOT NULL
);

CREATE INDEX idx_entries_mode ON entries(mode);
CREATE INDEX idx_entries_created ON entries(created_at DESC);
CREATE INDEX idx_entries_category ON entries(category);

-- 태그 (다대다)
CREATE TABLE tags (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  name  TEXT NOT NULL UNIQUE COLLATE NOCASE
);

CREATE TABLE entry_tags (
  entry_id  TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  tag_id    INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (entry_id, tag_id)
);

-- 위키링크 그래프 ([[link]] 추출)
CREATE TABLE links (
  source_id  TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  target_id  TEXT REFERENCES entries(id) ON DELETE SET NULL,
  target_text TEXT NOT NULL,                 -- 깨진 링크 보존
  PRIMARY KEY (source_id, target_text)
);

-- 전문 검색 (FTS5)
CREATE VIRTUAL TABLE entries_fts USING fts5(
  id UNINDEXED,
  title,
  body,
  tokenize = 'unicode61 remove_diacritics 2'
);

-- 한국어 검색을 위한 보조 인덱스
-- (FTS5의 unicode61은 한글 형태소 분리를 못 하므로
--  trigram 토크나이저나 Porter 변형 검토 필요)

-- 사용자 활동 통계 (대시보드용)
CREATE TABLE daily_stats (
  date          TEXT PRIMARY KEY,           -- YYYY-MM-DD
  memo_count    INTEGER DEFAULT 0,
  note_count    INTEGER DEFAULT 0,
  record_count  INTEGER DEFAULT 0,
  word_count    INTEGER DEFAULT 0
);

-- 마이그레이션 버전
CREATE TABLE schema_migrations (
  version  TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);
```

### 8.4 한국어 전문 검색 처리

SQLite FTS5의 기본 `unicode61` 토크나이저는 한글을 음절 단위로 잘라 검색 정확도가 떨어진다. 다음 중 하나를 채택한다.

**옵션 A: Trigram 토크나이저 (권장)**
- SQLite 3.34+ 내장 `trigram` 토크나이저 사용
- 부분 문자열 검색에 강함
- 인덱스 크기 다소 증가 (1.5~2배)

**옵션 B: Pre-tokenization**
- 한글 형태소 분석기(`mecab-ko`, `lucy-ko`)로 사전 분해
- Ruby 바인딩 부족 → C 확장 또는 외부 프로세스 필요
- MVP 범위 외 권장

**옵션 C: LIKE 폴백**
- FTS는 영문·태그용으로만 쓰고, 한글은 `WHERE body LIKE '%query%'` 사용
- 데이터 적을 때(< 5,000건)는 충분히 빠름

**MVP 권장**: 옵션 A + 옵션 C 폴백.

---

## 9. 옵시디언 통합 상세

### 9.1 옵시디언이 인식하는 핵심 요소

| 요소 | 옵시디언 동작 | 본 앱 처리 |
|------|---------------|------------|
| YAML frontmatter | 파싱하여 properties 패널 표시 | 모든 메타데이터를 frontmatter로 |
| `[[wiki link]]` | 클릭 가능한 내부 링크 | 자동완성 + DB에 그래프 저장 |
| `[[link\|alias]]` | 별칭 표시 | 동일 처리 |
| `#태그` | 태그로 인식, 사이드바 노출 | frontmatter `tags`와 본문 `#태그` 모두 추출 |
| `![[image.png]]` | 이미지 임베드 | `assets/` 경로 자동 정리 |
| `> [!note]` callout | 콜아웃 박스 렌더 | 템플릿에서 활용 가능 |
| 폴더 구조 | 사이드바 트리 | §8.2 구조 준수 |

### 9.2 옵시디언이 무시하는 영역

- `.obsidian/` 폴더 (옵시디언 설정)
- `.` 으로 시작하는 모든 파일·폴더

본 앱은 **`.sowing/` 폴더에 자체 메타데이터를 저장**하여 옵시디언과 충돌 없이 공존한다. 단, 옵시디언 사용자 중 일부는 "Show hidden files" 옵션을 켜므로, `.sowing/` 내부 파일도 사람이 읽기 좋은 형식(YAML/JSON)으로 유지한다.

### 9.3 옵시디언 ↔ 본 앱 동시 사용 시나리오

가장 빈번하고 중요한 사용 시나리오를 다룬다.

**시나리오 1: 사용자가 본 앱에서 메모 작성 → 옵시디언에서 편집**
1. 본 앱이 `00_Inbox/2026-05-07_092314.md` 생성
2. 사용자가 옵시디언으로 같은 파일 열고 편집·저장
3. 본 앱의 FileWatcher가 변경 감지 (debounce 500ms)
4. 파일 재파싱 → 인덱스 갱신
5. 본 앱 UI 자동 갱신 (Turbo Stream)

**시나리오 2: 사용자가 옵시디언에서 새 파일 생성**
1. 옵시디언이 frontmatter 없는 파일 생성 (예: `Untitled.md`)
2. FileWatcher가 새 파일 감지
3. 본 앱의 **Adoption Policy** 발동:
   - frontmatter 없으면 → 자동으로 `mode: note` 부여 + ULID 생성
   - 또는 사용자에게 "본 앱이 관리할까요?" 알림 (설정 가능)

**시나리오 3: 충돌 (양측 동시 편집)**
- 본 앱이 저장 직전에 file_mtime 재확인
- 메모리상 mtime ≠ 디스크 mtime인 경우 → 사용자에게 충돌 다이얼로그 (Keep mine / Keep theirs / Compare)

### 9.4 옵시디언 호환성 자동 검증

CI에 다음 체크를 포함한다.

```ruby
# spec/compatibility/obsidian_compat_spec.rb
RSpec.describe "Obsidian compatibility" do
  it "every generated file has valid YAML frontmatter" do
    fixture_files.each do |file|
      result = FrontMatterParser::Parser.parse_file(file)
      expect(result.front_matter).to be_a(Hash)
    end
  end

  it "wiki links resolve or are explicitly broken" do
    # ...
  end

  it "no Sowing-specific syntax leaks into body" do
    # ...
  end
end
```


---

## 10. UI/UX 가이드라인

### 10.1 디자인 원칙

1. **방해 최소화 원칙 (Minimal Friction)**: 메모 작성까지의 클릭/키 입력 횟수를 1~2회로 제한.
2. **빈 화면 금지 원칙 (No Empty State)**: 신규 사용자 첫 진입 시 항상 다음 행동 1개를 명확히 제시.
3. **점진적 노출 원칙 (Progressive Disclosure)**: 고급 기능(태그·링크·템플릿)은 사용자가 준비될 때 노출.
4. **교사 언어 원칙 (Domain Language)**: 모든 UI 문구는 교사가 일상에서 쓰는 표현으로. "Entry"가 아니라 "기록", "Frontmatter"가 아니라 "메타정보".

### 10.2 화면 흐름

```
[온보딩] → [대시보드(홈)] ⇄ [메모 빠른입력] (글로벌 단축키)
              │
              ├→ [필기 작성/편집]
              ├→ [기록 작성/편집]
              ├→ [모든 기록 목록 + 검색]
              ├→ [태그 탐색]
              ├→ [통계]
              └→ [설정]
```

### 10.3 핵심 화면 와이어프레임 (텍스트)

**대시보드**
```
┌─────────────────────────────────────────────────────────────┐
│  Sowing  | 홈  필기  기록  검색  통계  ⚙       [+ 빠른 메모]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  안녕하세요, 준기 선생님 👋                                 │
│  오늘은 5월 7일 목요일입니다                                │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ 오늘의 기록  │  │ 연속 기록일  │  │  자라는 숲   │        │
│  │     3건     │  │    🔥 12일   │  │   🌳 47그루  │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                             │
│  최근 메모                                                  │
│  ─────────────────────────────────                          │
│  • 09:23  1교시 수업이 평소보다 활기찼다...                 │
│  • 어제   수업 끝나고 민호와 짧은 대화...                   │
│  • 어제   3반 학급회의 안건 정리 필요...                    │
│                                                             │
│  📌 이 메모를 필기·기록으로 키워볼까요?                     │
│  [메모 → 기록으로 승격]                                     │
└─────────────────────────────────────────────────────────────┘
```

**빠른 메모 (모달)**
```
┌─────────────────────────────────────────────┐
│  💭 빠른 메모                          ESC ✕ │
├─────────────────────────────────────────────┤
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │                                     │   │
│  │  지금 떠오른 생각을 적어주세요...   │   │
│  │                                     │   │
│  │                                     │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  #태그추가 (선택)                           │
│                                             │
│             [Esc 취소]   [⌘+Enter 저장]    │
└─────────────────────────────────────────────┘
```

### 10.4 색상·타이포그래피

- **컬러 팔레트**: 차분한 자연 톤 (씨앗-숲 메타포 반영)
  - Primary: `#2D5F3F` (deep forest green)
  - Accent: `#D4A574` (warm seed gold)
  - Background: `#FAF8F3` (warm paper)
  - Text: `#2A2A2A`
- **다크모드**: Phase 2
- **타이포**: 본문은 `Pretendard` 또는 `Noto Sans KR`. 코드는 `JetBrains Mono`.
- **줄간격**: 1.7배 (긴 글 작성을 위한 가독성)

### 10.5 인터랙션 가이드

- 저장은 자동(autosave). 명시적 "저장" 버튼 없음. 단, 저장 직후 **시각적 피드백**(짧은 토스트 또는 잉크 마크 애니메이션) 필수.
- 위키링크 자동완성: `[[` 입력 후 200ms 디바운스, 최대 8개 결과 표시.
- 단축키는 옵시디언과 가능한 일치 (사용자가 자연스럽게 옵시디언으로 졸업하도록).

---

## 11. 모듈 및 디렉토리 구조

```
sowing/
├── Gemfile
├── Gemfile.lock
├── Rakefile
├── config.ru                    # Rack entry point
├── README.md
├── LICENSE
│
├── bin/
│   ├── sowing                   # 메인 실행 스크립트
│   └── sowing-doctor            # 진단 도구
│
├── config/
│   ├── application.rb           # 앱 부트스트랩
│   ├── routes.rb                # 라우트 정의
│   ├── locales/
│   │   └── ko.yml
│   └── settings.yml             # 기본 설정
│
├── lib/
│   └── sowing/
│       ├── version.rb
│       ├── application.rb       # Sinatra base
│       │
│       ├── domain/              # 도메인 객체 (의존성 없음)
│       │   ├── entry.rb
│       │   ├── memo.rb
│       │   ├── note.rb
│       │   ├── record.rb
│       │   ├── promotion_rules.rb
│       │   └── value_objects/
│       │       ├── ulid.rb
│       │       ├── tag_set.rb
│       │       └── wiki_link.rb
│       │
│       ├── use_cases/           # 비즈니스 로직
│       │   ├── create_memo.rb
│       │   ├── create_note.rb
│       │   ├── create_record.rb
│       │   ├── promote_entry.rb
│       │   ├── search_entries.rb
│       │   ├── apply_template.rb
│       │   └── reindex_vault.rb
│       │
│       ├── repositories/        # 영속성
│       │   ├── vault_repo.rb    # 마크다운 파일 I/O
│       │   ├── index_repo.rb    # SQLite 쿼리
│       │   └── template_repo.rb
│       │
│       ├── infrastructure/
│       │   ├── markdown/
│       │   │   ├── parser.rb
│       │   │   ├── renderer.rb
│       │   │   └── frontmatter.rb
│       │   ├── filesystem/
│       │   │   ├── safe_writer.rb     # 원자적 쓰기
│       │   │   └── file_watcher.rb
│       │   ├── search/
│       │   │   ├── fts_query.rb
│       │   │   └── tokenizer.rb
│       │   └── db/
│       │       ├── connection.rb
│       │       └── migrations/
│       │           ├── 001_create_entries.rb
│       │           ├── 002_create_tags.rb
│       │           └── ...
│       │
│       ├── controllers/
│       │   ├── application_controller.rb
│       │   ├── dashboard_controller.rb
│       │   ├── memos_controller.rb
│       │   ├── notes_controller.rb
│       │   ├── records_controller.rb
│       │   ├── search_controller.rb
│       │   └── settings_controller.rb
│       │
│       └── helpers/
│           ├── markdown_helper.rb
│           └── i18n_helper.rb
│
├── views/                       # ERB 뷰
│   ├── layouts/
│   │   └── application.erb
│   ├── dashboard/
│   ├── memos/
│   ├── notes/
│   └── ...
│
├── public/                      # 정적 자원
│   ├── css/
│   ├── js/
│   │   ├── application.js       # Stimulus controllers
│   │   └── controllers/
│   └── images/
│
├── templates/                   # 시스템 템플릿 (12종)
│   ├── lesson_reflection.md
│   ├── student_observation.md
│   └── ...
│
├── db/
│   └── schema.sql               # 참조용
│
├── spec/                        # RSpec
│   ├── domain/
│   ├── use_cases/
│   ├── repositories/
│   ├── system/                  # Capybara end-to-end
│   ├── compatibility/           # 옵시디언 호환 검증
│   └── support/
│
└── packaging/
    ├── tebako.yml
    ├── windows/
    │   └── installer.iss        # Inno Setup
    └── macos/
        └── Info.plist.template
```

### 11.1 Zeitwerk 자동 로딩

```ruby
# lib/sowing/application.rb
require "zeitwerk"
loader = Zeitwerk::Loader.new
loader.push_dir("#{__dir__}/..", namespace: Sowing)
loader.setup
```

### 11.2 모듈 명명 규칙

- 모든 클래스는 `Sowing::` 네임스페이스 하위.
- Use Case는 동사로 시작 (`CreateMemo`, `PromoteEntry`).
- Repository는 `Repo` 접미사.
- Value Object는 `value_objects/` 하위, 불변(frozen) 보장.

---

## 12. 개발 일정 및 마일스톤

8주 MVP 기준 일정안. 단일 풀타임 엔지니어 가정.

### Week 1-2: 기반 구축 (Foundation)
- [ ] 프로젝트 부트스트랩, Gemfile, 기본 라우트
- [ ] SQLite 마이그레이션, Sequel 모델
- [ ] 도메인 객체 (Entry, Memo, Note, Record)
- [ ] VaultRepo (마크다운 읽기/쓰기, frontmatter 처리)
- [ ] **Milestone**: CLI에서 `bin/sowing memo "테스트"`로 마크다운 파일 생성 가능

### Week 3-4: 핵심 기능 (Core Features)
- [ ] 빠른 메모 모달 + 글로벌 단축키
- [ ] 메모/필기/기록 CRUD
- [ ] 마크다운 에디터 (CodeMirror 6 기반) + 프리뷰
- [ ] 위키링크 자동완성
- [ ] **Milestone**: 메모 작성 → 필기 승격 → 기록 승격 흐름 동작

### Week 5: 검색·인덱싱 (Search & Indexing)
- [ ] FTS5 인덱스 구축
- [ ] 한국어 검색 처리 (trigram + LIKE 폴백)
- [ ] 태그 시스템
- [ ] **Milestone**: 5,000건 더미 데이터에서 검색 < 500ms

### Week 6: 옵시디언 통합·동기화 (Sync)
- [ ] FileWatcher 구현 + debounce
- [ ] 외부 변경 감지 → 인덱스 갱신
- [ ] 충돌 처리 다이얼로그
- [ ] **Milestone**: 본 앱과 옵시디언 동시 실행 시 양방향 동기화 검증

### Week 7: 대시보드·템플릿·온보딩
- [ ] 씨앗-숲 시각화
- [ ] 통계 (스트릭, 카운트)
- [ ] 12종 교사 템플릿 작성
- [ ] 첫 실행 마법사
- [ ] **Milestone**: 신규 사용자가 30분 내 첫 메모·필기·기록 모두 작성

### Week 8: 패키징·배포·QA
- [ ] Tebako 패키징 (Windows·macOS·Linux)
- [ ] Inno Setup 인스톨러 (Windows)
- [ ] DMG 빌드 (macOS, codesign·notarize)
- [ ] 공개 베타 5명 모집·피드백
- [ ] **Milestone**: 베타 사용자 100% 설치 성공, 70% 이상 1주 후 재방문

---

## 13. 테스트 전략

### 13.1 테스트 피라미드

```
       ▲ E2E (Capybara)
      ╱ ╲   ~ 30 케이스
     ╱   ╲  주요 사용자 흐름만
    ╱     ╲
   ╱───────╲ Integration
  ╱         ╲ ~ 100 케이스
 ╱  Service  ╲ Use Case + Repo 통합
╱─────────────╲
   Unit (Domain·Helpers)
       ~ 400 케이스
   순수 함수, 빠르고 많이
```

### 13.2 도메인 테스트 예시

```ruby
RSpec.describe Sowing::Domain::PromotionRules do
  describe "#can_promote?" do
    context "memo to note" do
      it "허용한다 - 카테고리·출처가 명시되면" do
        memo = build_memo(body: "수업이 좋았다")
        promotion = described_class.new(
          entry: memo,
          target_mode: :note,
          additions: { category: "lessons", source: "5월 7일 수학" }
        )
        expect(promotion.can_promote?).to be true
      end

      it "거부한다 - 카테고리가 누락되면" do
        # ...
      end
    end
  end
end
```

### 13.3 옵시디언 호환성 테스트

별도 `spec/compatibility/` 디렉토리에 격리. CI에서 옵시디언 CLI(가능한 범위)로 파일 검증.

```ruby
RSpec.describe "Obsidian compatibility", :compatibility do
  let(:fixture) { create_full_vault_fixture }

  it "frontmatter가 valid YAML이다" do
    Dir.glob("#{fixture}/**/*.md").each do |path|
      content = File.read(path)
      yaml = content.match(/\A---\n(.*?)\n---/m)&.[](1)
      expect { YAML.safe_load(yaml, permitted_classes: [Date, Time]) }
        .not_to raise_error
    end
  end

  it "wiki link target이 존재하거나 stub으로 표시된다" do
    # ...
  end

  it "위험 문자가 frontmatter에 escape된다" do
    # ULID 'O' 충돌, 콜론, 따옴표 등
  end
end
```

### 13.4 동기화 회복 테스트 (Chaos)

`spec/chaos/` 하위에 다음 시나리오를 자동화한다.

- 쓰기 도중 강제 종료 (kill -9) 후 재시작 → 일관성 검증
- 디스크 공간 부족 시뮬레이션
- 외부 프로세스가 같은 파일을 동시 수정 (mtime 경합)
- SQLite 파일 손상 → 마크다운에서 인덱스 재구축

---

## 14. 패키징 및 배포

### 14.1 Tebako 패키징

```yaml
# packaging/tebako.yml
project_name: sowing
entry_point: bin/sowing
ruby_version: "3.3.0"
license: MIT
output: dist/sowing
```

빌드 명령:
```bash
tebako press --root . --entry bin/sowing --output dist/sowing-${VERSION}-${OS}
```

### 14.2 OS별 인스톨러

| OS | 도구 | 산출물 |
|----|------|--------|
| Windows | Inno Setup | `Sowing-Setup-1.0.0.exe` |
| macOS | `create-dmg` + codesign + notarize | `Sowing-1.0.0.dmg` |
| Linux | AppImage | `Sowing-1.0.0.AppImage` |

### 14.3 자동 업데이트

- GitHub Releases 기반 (서명 검증 필수)
- 앱 시작 시 비동기 체크 (24시간 throttle)
- 사용자 명시 동의 후 다운로드·교체

---

## 15. 위험 요소 및 대응

| 위험 | 영향도 | 가능성 | 대응 |
|------|--------|--------|------|
| 마크다운 ↔ SQLite 동기화 깨짐 | 높음 | 중 | §7.3 동기화 전략, 부팅 시 검증, chaos 테스트 |
| 한국어 FTS 정확도 부족 | 중 | 높음 | trigram + LIKE 폴백, Phase 2에 mecab-ko 검토 |
| Tebako 빌드 실패 (특히 macOS) | 높음 | 중 | 백업으로 native gem 번들 + ruby_installer 병행 |
| 옵시디언 사양 변경으로 호환성 깨짐 | 중 | 낮음 | compatibility CI, 옵시디언 메이저 릴리즈 모니터링 |
| 사용자가 볼트 위치를 모르고 잃어버림 | 중 | 중 | 온보딩에서 위치 명시 + 대시보드에 항상 표시 + 백업 알림 |
| 글로벌 단축키 OS 충돌 | 낮음 | 중 | 첫 실행 시 충돌 감지·대안 제안 |
| 크로스플랫폼 한글 파일명 (NFC/NFD) | 중 | 높음 | macOS는 NFD, Windows/Linux는 NFC. 저장 시 NFC 강제 정규화 |

---

## 16. 향후 확장 (Roadmap Sketch)

- **Phase 2 (M+3)**: 일일 회고 알림, OCR, 다크모드, 백업/복원
- **Phase 3 (M+6)**: 로컬 LLM(Ollama) 연동 — 자동 태그 제안, 회고 질문 생성
- **Phase 4 (M+9)**: 모바일 앱 (Flutter, 동일 볼트 동기화)
- **Phase 5 (M+12)**: 학교 단위 라이선스, 동료 교사와 선택적 공유 (옵션)

---

## 17. 부록

### 17.1 용어 사전

| 용어 | 의미 |
|------|------|
| Vault | 사용자의 모든 마크다운 파일이 저장되는 루트 디렉토리. 옵시디언 용어 차용. |
| Entry | 메모·필기·기록을 모두 포함하는 도메인 추상 |
| Promote | 메모 → 필기 → 기록 단계로 승격하는 행위 |
| Frontmatter | 마크다운 파일 상단의 YAML 메타데이터 블록 |
| Wiki Link | `[[파일이름]]` 문법의 옵시디언 내부 링크 |
| FTS | Full-Text Search. SQLite의 FTS5 가상 테이블 사용 |

### 17.2 참고 자료

- Obsidian Help: https://help.obsidian.md
- Obsidian File Format: https://help.obsidian.md/Files+and+folders/Accepted+file+formats
- CommonMark Spec: https://spec.commonmark.org
- SQLite FTS5: https://www.sqlite.org/fts5.html
- Tebako: https://github.com/tamatebako/tebako
- Sequel Documentation: https://sequel.jeremyevans.net
- Hotwire: https://hotwired.dev

### 17.3 착수 전 결정사항 (2026-05-07 확정)

상세 근거는 [`docs/DECISIONS.md`](DECISIONS.md) 참조.

| # | 결정사항 | ADR |
|---|---------|-----|
| 1 | **일일 노트(Daily Note) MVP 미포함**. Phase 2 이후 검토. | ADR-003 |
| 2 | **위키링크 자동완성에 메모 파일도 포함**. 모드별 시각 구분 표시. | ADR-004 |
| 3 | **첫 실행 시 샘플 콘텐츠 12종 자동 생성** (사용자 동의 후). | ADR-005 |
| 4 | **클라우드 동기화 가이드를 앱이 직접 제공** (iCloud/OneDrive/Dropbox/Syncthing 4종). | ADR-006 |
| 5 | **백엔드는 Sinatra 로컬 웹 서버** + Hotwire 프론트엔드 채택. | ADR-002 |

---

**문서 끝.**

본 명세서는 살아있는 문서다. 구현 과정에서 도출되는 의사결정은 본 문서에 즉시 반영하고, 변경 이력을 GitHub PR로 추적할 것을 권장한다.

