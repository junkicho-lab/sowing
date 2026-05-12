# Sowing 🌱 사용자 매뉴얼

> **v0.1.8 (2026-05-12) 기준 · 실용 reference**
> 처음이라면 → [USER_GUIDE.md](USER_GUIDE.md) (스토리텔링 + 철학)
> 빠른 참조를 원하면 → 이 문서 (단계별 사용법 + cheat sheet)

목차:
1. [빠른 시작 (5분)](#1-빠른-시작-5분)
2. [Nav 한눈에 — 5+1 동사](#2-nav-한눈에--51-동사)
3. [4 mode 작성법](#3-4-mode-작성법)
4. [단축키](#4-단축키)
5. [17 합성기 사용법](#5-17-합성기-사용법)
6. [자기 거울 (5축)](#6-자기-거울-5축)
7. [회상 — 검색·태그·그래프·매트릭스](#7-회상--검색태그그래프매트릭스)
8. [설정 reference](#8-설정-reference)
9. [옵시디언 동시 사용](#9-옵시디언-동시-사용)
10. [모바일·다크모드](#10-모바일다크모드)
11. [트러블슈팅](#11-트러블슈팅)
12. [Cheat Sheet (appendix)](#12-cheat-sheet-appendix)

---

## 1. 빠른 시작 (5분)

### 1.1 설치 확인

```sh
git clone https://github.com/junkicho-lab/sowing.git
cd sowing && bundle install && bundle exec rake db:setup
bin/sowing dev
# 브라우저: http://127.0.0.1:48723
```

또는 Docker:

```sh
docker pull ghcr.io/junkicho-lab/sowing:0.1.8
docker run -d -p 48723:48723 -v ~/Documents/SowingVault:/vault ghcr.io/junkicho-lab/sowing:0.1.8
```

### 1.2 첫 메모 한 줄

1. 어떤 화면에서든 **`⌘ + Shift + M`** (Mac) / **`Ctrl + Shift + M`** (Windows/Linux)
2. 모달 창에 한 줄
3. **Enter** → 저장 (`00_Inbox/` 폴더에 마크다운 파일로)

끝. 결정 0건.

### 1.3 첫 5분 권장 흐름

```
① ⌘⇧M 으로 메모 한 줄
② Settings (⚙) → 호칭·학급명단 입력
③ Settings → 🌗 테마 선택
④ /tutorial 3분 인터랙티브 (선택)
⑤ /synth 진입해서 17 합성기 둘러보기
```

---

## 2. Nav 한눈에 — 5+1 동사

```
🏠 홈   🖊 글쓰기 ▾   📚 쓴 글 보기 ▾   🗓 쓸 글 계획 ▾   🪞 자기 거울 ▾   ⚙ 설정
```

| Nav | 동사 | 핵심 진입점 |
|---|---|---|
| 🏠 홈 (`/`) | "오늘 뭐 일어났지?" | 통계 + 새싹 + 오늘 할 일 + 오늘의 자기 |
| 🖊 글쓰기 (`/write`) | "지금 적자" | 빠른메모·책·강의·감정·학생·음성·필기 |
| 📚 쓴 글 보기 (`/view`) | "그때 그거 어디?" | 최근·카테고리·매트릭스·timeline·태그·그래프·검색 |
| 🗓 쓸 글 계획 (`/plans`) | "내일 뭐?" | 일간·주간·월간·프로젝트·학기 |
| 🪞 자기 거울 (`/mirror`) | "내가 누구?" | 합성기 17종·사용 지표·오늘의 자기 |
| ⚙ 설정 (`/settings`) | "조정" | 호칭·학급명단·LLM·테마·단축키·거울·백업 |

기존 URL (`/memos`, `/notes`, `/records`, `/tags`, `/search`, `/synth`, `/graph`) 모두 그대로 작동 — 북마크·외부 링크 영향 0.

---

## 3. 4 mode 작성법

```
00_Inbox/        ← 💭 메모 (휘발, 며칠~몇 주)
20_Notes/        ← 📝 필기 (한 학기, 카테고리 분류)
30_Records/      ← 📖 기록 (30년 누적, 카테고리·연도 분류)
40_Plans/        ← 🗓 계획 (미래, 일·주·월·프로젝트·학기)
```

### 3.1 💭 메모 (빠른 메모)

#### 진입 방법 3가지

1. **`⌘⇧M`** (어디서든) → 모달 → 한 줄 → Enter
2. Nav **🖊 글쓰기 ▾** → ⚡ 빠른 메모
3. 외부 링크 `/write/general` → 모달 자동 열림

#### 5 subtype chip (Phase 13 W26-T01)

| Chip | 자동 추가 | slot field |
|---|---|---|
| ⚡ 일반 | (없음) | (없음) |
| 📖 책 | `#책기록` | 제목 + 페이지 |
| 🎤 강의·연수 | `#강의기록` | 강사 + 주제 |
| 💭 감정 | `#감정` | 18종 chip 선택 |
| 👤 학생 | `#학생관찰` + `#학생이름` | 학생명 |

각 chip 클릭 시 슬롯 입력란 표시 → 본문 작성 후 저장하면 자동 결합:

```
📖 책 chip 예시:
**📖 책:** 사피엔스
**페이지:** 42

인간만이 허구를 믿는다

#책기록
```

#### 🎙 음성 입력 (Phase 13 W26-T02)

- Chrome / Edge 만 (Web Speech API)
- ko-KR 한국어 인식
- 인터넷 필요 (Google 서버 경유)
- 빠른 메모 모달 안 🎙 버튼 → 마이크 권한 허용 → 발화
- textarea 에 실시간 표시 → 사용자가 확인·편집 후 저장

### 3.2 📝 필기 (작업 중인 노트)

진입: Nav **🖊 글쓰기 ▾** → 📝 필기 작성

- 카테고리 필수: `lessons`, `meetings`, `books`, `trainings`, 자유 입력
- CodeMirror 6 마크다운 에디터 + 실시간 프리뷰
- 위키링크 `[[...]]` 자동완성
- 저장 위치: `20_Notes/{카테고리}/{title}.md`

### 3.3 📖 기록 (30년 영구 보존)

승격 흐름:
1. 메모 또는 필기 카드의 **📖 기록 승격** 버튼
2. 또는 직접 `/records/new`
3. 카테고리 필수, 연도는 자동 (`30_Records/{YYYY}/{카테고리}/...`)

### 3.4 🗓 계획 (Phase 13 W27 + v0.1.8)

#### 5 period

```
🗓 쓸 글 계획 ▾
├── 📅 일간      40_Plans/daily/{YYYY-MM-DD}-{HHmm}-{id4}.md
├── 📋 주간      40_Plans/weekly/{YYYY-Www}-{HHmm}-{id4}.md
├── 🎯 월간      40_Plans/monthly/{YYYY-MM}-{HHmm}-{id4}.md
├── 🏗 프로젝트   40_Plans/project/{slug}-{id4}.md
└── 🎓 학기      40_Plans/semester/{YYYY-Sn}-{id4}.md
```

#### 같은 날짜에 여러 plan (v0.1.8)

같은 날짜에 plan 을 여러 개 만들면 **자동으로 오전·오후 분류**:

```
📅 2026-05-12 (총 3건)
  🌅 오전 (2건)
    ⌚ 09:30  협동학습 평가 루브릭
    ⌚ 11:00  도덕수업 준비
  🌆 오후 (1건)
    ⌚ 14:00  학부모 면담
```

기준: 작성 시각 (`created_at.hour < 12` → 오전)

#### 완료 토글

각 plan 상세 페이지 → **✅ 완료 표시** 버튼. 다시 누르면 진행 중으로 복귀. **사용자 명시 클릭만** (ADR-013).

#### 오늘 할 일 위젯

대시보드 첫 화면에 오늘 미완료 daily plan 자동 표시.

---

## 4. 단축키

### 4.1 기본 단축키

| 단축키 | 동작 |
|---|---|
| `⌘⇧M` (Mac) / `Ctrl⇧M` | 빠른 메모 모달 |
| `⌘K` (Mac) / `CtrlK` | 빠른 검색 |
| `⌘Enter` / `CtrlEnter` | 모달 안에서 폼 제출 |
| `Esc` | 모달 닫기 |

### 4.2 사용자 정의 (Phase 14 W30, v0.1.5)

`/settings → ⌨ 단축키` 에서 마지막 1글자 변경 가능:

| 동작 | 기본 → 변경 예시 |
|---|---|
| 빠른 메모 | `⌘⇧M` → `⌘⇧J` |
| 빠른 검색 | `⌘K` → `⌘P` |

**제약**: modifier (Cmd⇧) 고정, 마지막 1 영문 글자만 (a-z). 충돌 방지.

옵시디언이 이미 `⌘⇧M` 사용 중이면 → Sowing 의 메모를 `⌘⇧J` 같은 다른 글자로.

---

## 5. 17 합성기 사용법

`/synth` 또는 Nav **🪞 자기 거울 ▾ → 🌱 합성기 16종**

### 5.1 17 type 목록

| 분류 | 합성기 | 입력 | 결정적 | LLM |
|---|---|---|---|---|
| 학생 | 학생 디제스트 (#1) | 학생 mention | 인용·시간순 | 4 섹션 해석 |
| 학생 | 학생 묘사 변화 (#7) | 시간 차이 인용 | 변화 시점 후보 | 패턴 해석 |
| 학기 | 학기 회고 (#2) | 학기 entries | 통계·키워드 | 4 영역 narrative |
| 수업 | 수업 패턴 (#3) | 수업 카테고리 | top 키워드 | 4 섹션 |
| 수업 | 수업 시리즈 (#6) | 단원 차시 | timeline | 단원 회고 |
| 수업 | 학습 진척 추이 (#11) | 차시 시계열 | pace 분석 | — |
| 학부모 | 상담 준비 (#1) | 학생 mention | 면담 시점 | 다음 질문 후보 |
| 학부모 | 상담 패턴 (#9) | 학기 상담 | 학생별 빈도 | 4 섹션 |
| 평가 | 평가 누적 (#2) | 평가 records | 점수 추이 | — |
| 연수 | 연수 흡수 (#3) | 연수 mention | 적용 사례 | — |
| 횡단 | 주간 회고 (#4) | 1주 entries | 통계 | 회고 narrative |
| 횡단 | 고립 메모 (#5) | backlink 0 노트 | 후보 목록 | — |
| 횡단 | 태그 클러스터 (#7) | 태그 통계 | 의미적 cluster | — |
| 횡단 | 계절성 (#8) | 월별 분포 | 패턴 | — |
| 메타 | 자기 회고 패턴 (#10) | 큰 기간 본문 | 톤 + 공백 | 4 섹션 단정 거부 |
| 메타 | 사건 인과 추론 (#12) | 사건 keyword window | before/after | 가능 상관 |
| **거울** | **🌅 자기 거울 (5축) #17** | **1일 / 1주** | **5축 통계** | **5축 해석** |

### 5.2 LLM 모드 (선택)

5 합성기가 LLM 토글 지원 (parent-patterns / self-patterns / event-causality / contradictions / self-mirror):

1. `.env` 에 `ANTHROPIC_API_KEY=sk-ant-...`
2. 앱 재시작
3. `/synth` 의 해당 폼에 **🌱 LLM 모드** 체크박스 표시
4. 모델 선택 (드롭다운):

| 모델 | 합성 1건당 비용 | 속도 |
|---|---|---|
| Haiku 4.5 (default) | $0.0080 | 2~5초 |
| Sonnet 4.5 | $0.0240 | 5~10초 |
| Opus 4.7 | $0.1200 | 15~30초 |

체크 안 하면 **결정적 모드** (즉시·무료). API 키 없어도 17종 모두 결정적 모드로 작동.

### 5.3 검토 → 수락/거절

생성된 합성 결과는 `.sowing/synth/{type}/...` **검토 대기**:

- **자세히 보기** — 마크다운 + 위키링크 렌더링 (변경 0)
- **수락** — `30_Records/{YYYY}/{accept_category}/` 로 이동 (정식 기록)
- **거절** — `.sowing/trash/` 30일 자동 삭제

ADR-013: **사용자 명시 클릭 없이는 정식 기록 안 됨**.

---

## 6. 자기 거울 (5축)

### 6.1 5축

| # | 축 | 내용 |
|---|---|---|
| 1 | 🧠 지성 | 자주 환기한 키워드 top 5 |
| 2 | 💭 감정 | POSITIVE/NEGATIVE 신호어 카운트 + 비율 |
| 3 | 🔁 습관 | 시간대 + 카테고리·모드 분포 |
| 4 | 🤝 관계 | entity_mentions top 5 (학생·동료) |
| 5 | ⚡ 에너지 | 작성 빈도 + 일평균 + 날짜 수 |

### 6.2 매일 자동 거울 (opt-in)

`/settings → 🪞 자기 거울` 체크박스 ON 시:
- 매일 대시보드 첫 진입 → 오늘 entries ≥ 3 이면 **자동 생성**
- 결과는 `.sowing/synth/self-mirror/daily-{date}.md` 검토 대기
- 대시보드 위젯에 5축 요약 즉시 표시

### 6.3 수동 생성

`/synth` 페이지에서 자기 거울 폼:
- 기간: 📅 오늘 (daily) / 📋 이번 주 (weekly)
- 날짜 (선택, 비우면 오늘)
- LLM 모드 체크 (선택)
- 생성 → `.sowing/synth/self-mirror/{period}-{date}.md`

---

## 7. 회상 — 검색·태그·그래프·매트릭스

### 7.1 검색 (`/search`, `⌘K`)

- SQLite FTS5 한국어 trigram + LIKE 폴백
- 메모/필기/기록/계획/합성 모두 검색

### 7.2 태그 cloud (`/tags`)

본문의 `#태그` 가 자동 인덱싱. 클릭하면 해당 태그 entries 전체.

### 7.3 위키링크 그래프 (`/graph`)

- `[[...]]` 로 연결된 entries 시각화
- mode 필터 · 카테고리 필터 · 기간 필터
- force-directed SVG, JS 자체 구현 (외부 라이브러리 0)

### 7.4 카테고리 × 연도 매트릭스 (`/records/by-category`)

30년 누적 분포를 한 화면. 카테고리 × 연도 셀 클릭 → timeline 진입.

### 7.5 Timeline (`/records/timeline`)

일별 평면 (31×N 그리드). 카테고리·연도 필터.

### 7.6 통합 시간순 (`/view/recent`)

메모 + 필기 + 기록 + **계획** 한 줄에 시간순. mode chip / 카테고리 chip 필터.

---

## 8. 설정 reference (`/settings`)

| 섹션 | 내용 |
|---|---|
| 👤 프로필 | 호칭 (템플릿의 `{{user}}`) |
| 👥 학급 명단 (W17-T03) | 학생 이름 목록. 4주 미언급 알림. |
| ⌨ 단축키 (W30) | 빠른 메모·검색 키 1글자 변경 |
| 🌗 테마 (W29) | auto (OS) / light / dark |
| 🪞 자기 거울 (W28) | 매일 자동 5축 분석 ON/OFF |
| 🎓 튜토리얼·온보딩 | 3분 인터랙티브 다시 보기 |
| 🗑 샘플 정리 | 온보딩 시드 샘플 휴지통으로 |

### 8.1 LLM 모드

`/settings` 페이지엔 UI 없음. `.env` 파일 (프로젝트 루트):

```bash
# Anthropic API (https://console.anthropic.com)
ANTHROPIC_API_KEY=sk-ant-...
# 선택 — 기본 모델 변경
# ANTHROPIC_MODEL=claude-sonnet-4-5-20250929
```

앱 자동 로딩 (export 불필요). 손상돼도 결정적 모드로 graceful fallback.

### 8.2 백업

```
~/Documents/SowingVault/   ← 이 폴더만 백업하면 충분
├── 00_Inbox/              마크다운 (SoT)
├── 20_Notes/
├── 30_Records/
├── 40_Plans/
├── 10_Templates/
└── .sowing/               인덱스·합성·휴지통 (재구축 가능)
```

iCloud Drive / Dropbox / Google Drive 안에 두면 자동 동기화.

---

## 9. 옵시디언 동시 사용

Sowing vault 가 곧 옵시디언 vault. 양방향 호환:

- 옵시디언 vault 경로를 `~/Documents/SowingVault/` 로 지정
- 위키링크 `[[...]]` 모두 동일 인식
- 태그 `#tag` 동일
- 마크다운 todo 체크박스 `- [ ]` / `- [x]` 동일

### 충돌 회피

- 외부 변경 (옵시디언) → Listen gem 이 감지 → Sowing 인덱스 자동 갱신
- 같은 파일 동시 편집 → 충돌 다이얼로그 (W5-T05)

---

## 10. 모바일·다크모드

### 10.1 모바일 (Phase 14 W31, v0.1.6)

```sh
# 같은 네트워크의 폰에서 접속:
bin/sowing dev --host 0.0.0.0
# 폰 브라우저: http://{Mac IP}:48723
```

UI 자동 적응 (≤ 768px):
- 햄버거 메뉴 (☰) 노출
- nav 가 vertical drawer 로
- chip 들 모두 ≥ 40px (Apple HIG)
- 카드 패딩 확대

### 10.2 다크 모드 (Phase 14 W29, v0.1.4)

`/settings → 🌗 테마`:
- **auto** (default): OS 자동 (`prefers-color-scheme: dark`)
- **light**: 강제 라이트 (워밍 페이퍼)
- **dark**: 강제 다크 (딥 포레스트)

브랜드 색 (`--color-primary` 초록, `--color-accent` gold) 은 두 테마 모두 동일.

---

## 11. 트러블슈팅

### 11.1 검색이 0건

```sh
bin/sowing-doctor       # 진단
bin/sowing reindex      # 인덱스 재구축
```

### 11.2 합성기 생성 실패

| 실패 코드 | 의미 | 조치 |
|---|---|---|
| `:no_entries` | 기간·키워드 매칭 entries 부족 | 기간 확대 또는 시드 더 작성 |
| `:no_observations` | 학생 entity 부재 | 학급 명단 등록 후 학생 이름 본문에 포함 |
| `:invalid_keyword` | 키워드 부적합 | 영문/숫자/한글만 사용 |
| `:too_many_entries` | 5000+ — 합성 부담 | 기간 축소 |

### 11.3 LLM 모드 토글 안 보임

`.env` 의 `ANTHROPIC_API_KEY` 값 확인 → 앱 재시작. 부팅 시 자동 로딩됨.

### 11.4 모달 안 열림

빠른 메모 모달 (`⌘⇧M`) 이 안 열리면:
- 단축키 변경됐는지 `/settings → ⌨ 단축키` 확인
- 브라우저 콘솔에 `window.SOWING_SHORTCUTS` 확인

### 11.5 같은 날짜 plan 충돌 (v0.1.7 이전)

v0.1.8 부터 자동 해결. 그 이전 버전이면 업그레이드:

```sh
git pull origin main && bundle install && bundle exec rake db:migrate
```

### 11.6 데이터 손실 걱정

마크다운 파일 자체가 SoT. SQLite 깨져도 `bin/sowing reindex` 로 재구축. **vault 폴더 백업이 절대 진실**.

---

## 12. Cheat Sheet (appendix)

### 12.1 단축키

```
⌘⇧M      빠른 메모 모달
⌘K       빠른 검색
⌘⏎       모달 안 폼 제출
Esc      모달 닫기 / 햄버거 닫기
```

### 12.2 핵심 라우트

```
GET /                       대시보드 (통계·새싹·오늘 할 일·오늘의 자기)
GET /memos                  메모 목록
GET /notes                  필기 목록
GET /records                기록 목록 (카테고리 chip 필터)
GET /records/by-category    📊 카테고리 × 연도 매트릭스 (30년)
GET /records/timeline       📅 timeline (일별 평면)
GET /plans?period=daily     계획 — 일간 (오전/오후 grouping)
GET /plans/new              새 계획 작성
GET /view/recent            🕐 메모/필기/기록/계획 통합 시간순
GET /tags                   🏷 태그 클라우드
GET /graph                  🕸 위키링크 그래프
GET /search?q=...           🔍 검색
GET /synth                  🌱 합성기 17종 검토 대기
GET /synth/metrics          📊 사용 지표 (베타 검증)
GET /settings               ⚙ 설정
```

동사 라우트 (Phase 13 W25):
```
/write          → 모달 자동 열기
/write/{type}   → chip prefill (book/lecture/emotion/student/general)
/view           → /view/recent redirect
/plan           → /plans redirect
/mirror         → /synth redirect
```

### 12.3 mode 색상 코드

| Mode | 색 | 토큰 |
|---|---|---|
| 💭 메모 | amber | `rgb(217, 119, 6)` |
| 📝 필기 | blue | `rgb(37, 99, 235)` |
| 📖 기록 | green | `var(--color-primary)` |
| 🗓 계획 | purple | `rgb(168, 85, 247)` |

### 12.4 vault 폴더 구조

```
~/Documents/SowingVault/
├── 00_Inbox/                           메모
├── 10_Templates/                       템플릿 12종
├── 20_Notes/{카테고리}/                필기
├── 30_Records/{YYYY}/{카테고리}/       기록 (30년)
├── 40_Plans/
│   ├── daily/{date}-{HHmm}-{id4}.md
│   ├── weekly/{YYYY-Www}-{HHmm}-{id4}.md
│   ├── monthly/{YYYY-MM}-{HHmm}-{id4}.md
│   ├── project/{slug}-{id4}.md
│   └── semester/{YYYY-Sn}-{id4}.md
└── .sowing/                            인덱스·합성·휴지통
    ├── synth/{type}/                   17 합성기 검토 대기
    ├── trash/                          30일 자동 삭제
    └── audit.log                       모든 변경 추적
```

### 12.5 진단 도구

```sh
bin/sowing-doctor             # 전체 진단 (vault 정합성·인덱스·LLM 키 등)
bin/sowing reindex            # 인덱스 재구축
bin/sowing-release-check      # 출시 전 게이트 (rspec·lint·5x stress·doctor·eval)
bin/sowing-mcp                # MCP 서버 (Claude Desktop / Codex / Continue 연동)
bin/sowing-install            # 한 줄 설치 스크립트
```

### 12.6 ADR 핵심 (의사결정)

| ADR | 한 줄 |
|---|---|
| 001 | 마크다운 SoT (옵시디언 호환) |
| 009 | 로컬-first (LLM 옵션만 클라우드) |
| 013 | 자율 mutation 0 (사용자 명시 클릭) |
| 014 | 동사 중심 IA (명사 mode = 저장 단위, 동사 nav = 의도) |

전체: [docs/DECISIONS.md](DECISIONS.md)

### 12.7 출시 history

| Tag | 핵심 |
|---|---|
| v0.1.0 | 첫 정식 release (Phase 9~12) |
| v0.1.1 | LLM 통합 강화 (.env 자동·UI toggle·모델 선택) |
| v0.1.2 | Phase 13 — 동사 IA + Plan + 17번째 합성기 |
| v0.1.3 | Plan IndexRepo 통합 |
| v0.1.4 | Phase 14 PoC: 다크 모드 + 베타 인터뷰 가이드 |
| v0.1.5 | Phase 14: 단축키 사용자 정의 |
| v0.1.6 | Phase 14: 모바일 햄버거 + 터치 chip |
| v0.1.7 | Hotfix: Plan UNIQUE 충돌 |
| **v0.1.8** | **Plan 같은 날짜 여러 개 + 오전/오후 grouping** |

---

## 13. 추가 자료

- [USER_GUIDE.md](USER_GUIDE.md) — 입문 가이드 (스토리텔링 + 캡쳐 13장 + 범주 중심 흐름)
- [REDESIGN_IA.md](REDESIGN_IA.md) — Phase 13 IA 재설계 설계
- [BETA_GUIDE.md](BETA_GUIDE.md) — 베타 검증 측정 기준
- [BETA_PHASE13_INTERVIEW.md](BETA_PHASE13_INTERVIEW.md) — 한 학기 후 인터뷰 가이드
- [DECISIONS.md](DECISIONS.md) — ADR 14건
- [SPEC.md](SPEC.md) — 전체 기술 명세
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md) — 알려진 제약사항

---

**한 줄**: 매일 ⌘⇧M 한 번 = 30년 누적의 시작. 🌱
