# Changelog

All notable changes to Sowing 🌱 will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

(다음 릴리스 변경사항 누적용 — 비어 있으면 최근 릴리스가 모두 반영됨.)

## [0.3.0] - 2026-05-12 — Phase 16 UI 통합 + 생기부 자동화

v0.2.0 의 Phase R Bounded Context 인프라가 비로소 사용자 손에 닿음.
비전 D 의 4 단계 (쓰기·정리·통찰·출력) 가 UI 로 1:1 매핑됨. 7 commits / 0 spec
회귀 / 2005 examples / 0 failures.

### 🌱 비전 D 통합 라이프사이클 완성

| 단계 | UI | Phase R BC | 동작 |
|---|---|---|---|
| D.1 쓰기 | quick_modal + subject 4축 | Capture | `Capture.create_item(subject:)` |
| D.2 정리 | 📦 보관 버튼 + /archive | Knowledge | `Knowledge.archive(reason:)` |
| D.3 통찰 | /synth (Phase 11) | Insight | 18 synthesizers |
| D.4 출력 | 📋 공식 양식 + 📥 내보내기 + ✨ 디제스트 연계 | Output | `Output.generate(format:)` |

### R4b-followup — Output PDF + DOCX (markdown-only → 3 format 완성)

v0.2.0 의 markdown-only MVP 를 Prawn (PDF) + caracal (DOCX) 로 확장.
5 templates × 3 formats 모두 작동.

**핵심 추가**:
- `Output::PdfRenderer` — commonmarker AST → Prawn DSL walker
  - Pretendard 한글 폰트 등록 (Regular + Bold)
  - H1/H2/H3 / paragraph / bold·italic / list / table / hr 모두 지원
  - prawn-table 통합 (budget_request 행 단가 테이블 렌더)
- `Output::DocxRenderer` — commonmarker AST → caracal DSL walker
  - caracal 의 h1~h6 / p / ul / table helper 매핑
  - 인라인 bold/italic, 시스템 폰트 자동 fallback
- `Output::FontConfig` — 한글 폰트 resolver
  - ENV `SOWING_PDF_FONT` > vendored Pretendard > macOS/Linux 시스템 fallback
  - `FontNotFound` 시 친절한 설치 가이드 메시지

**vendored 폰트 (`vendor/fonts/`)** — 약 5.3 MB:
- `Pretendard-Regular.ttf` + `Pretendard-Bold.ttf` (SIL OFL-1.1)
- 시스템 한글 폰트 (AppleGothic·NotoCJK) 의 ttfunk OS/2 table 호환 이슈 회피

**Gemfile 변경**:
- 추가: `prawn ~> 2.5`, `prawn-table ~> 0.2`, `caracal ~> 1.4`
- **제거: `r18n-core ~> 6.0`** — 실제 미사용 + bigdecimal 버전 제약이
  prawn 2.5 (ttfunk 1.8) 와 충돌. 향후 i18n 필요 시 r18n 5.x 또는 다른 gem.

**Façade 변경**:
- `Sowing::Output.generate(format: :pdf)` — PDF binary 반환 (또는 write_to 시 파일)
- `Sowing::Output.generate(format: :docx)` — DOCX binary 반환
- 이전의 `NotImplementedError` stub 폐기

**Spec (+38)**:
- `spec/output/pdf_renderer_spec.rb` (14): 마크다운 features 5 종 + 5 templates 통합
- `spec/output/docx_renderer_spec.rb` (11): 동일 features + 5 templates 통합
- `spec/output/font_config_spec.rb` (6): resolve / available? / ENV override
- 갱신: stage_1, stage_4b — NotImplementedError 검증 → 실 binary 검증
- 1903 → 1944 (+41)

### Phase 16 — UI 통합 + 생기부 기능 (6 tasks)

**P16-T01: 내보내기 UI**
- `/records/:id/export?format=markdown|pdf|docx` + `/notes/:id/export?...`
- record/note show 페이지에 "📥 내보내기" details/summary dropdown
- 한글 파일명 RFC 5987 (filename*=UTF-8''<encoded>) — 옛 브라우저 ASCII fallback

**P16-T02: Subject 4축 quick_modal**
- 빠른 메모 모달에 `<select name="subject">` (4 옵션 + 없음)
  - person 👤 인물 / subject 📚 교과 / document 📄 문서 / identity 🪞 정체성
- POST /memos 가 subject 파라미터 수신 → `Capture.create_item(subject:)`
- DB entries.subject ENUM 자동 채움 (Phase R Stage 2 R2-T05 인프라 활용)

**P16-T03: Archive UI**
- POST /records/:id/archive (사유 입력) / POST /records/:id/unarchive
- GET /archive — 보관된 entries 통합 목록 (mode 별 아이콘 + 복원 버튼)
- record show 에 "📦 보관" form + confirm dialog
- 보관 후 /records 등 일상 페이지 자동 제외 (Phase R Stage 3 R3-T05 활용)
- 영구 삭제 0 — 30년 보존 (CLAUDE.md 원칙 5)
- nav 보조 그룹 "···" 에 보관함 진입점

**P16-T04: 공식 양식 생성 UI**
- GET /generate — 5 카드 landing
- 5 dedicated form 뷰: student_record / consultation / meeting_minutes /
  project_proposal / budget_request
- POST /generate/:template → markdown/pdf/docx 다운로드
- budget_request 의 line_items 동적 표 (5행 grid)
- meeting_minutes 의 안건·결정사항 multi-line 입력 자동 split
- nav 메인 그룹 "📋 공식 양식"

**P16-T05: 생기부 자동 채우기 (끝판왕)**
- GET /generate/student_record?student=NAME → 1년치 entries 자동 수집
- `IndexRepo.search_with_filters(q: NAME)` 활용 (한글 비율 자동 라우팅)
- LEARNING_KEYWORDS (수업·발표·학습·평가 등) → learning_activities textarea
- BEHAVIORAL_KEYWORDS (친구·관계·태도 등) → behavioral_observations textarea
- 본문에 학생 이름 포함된 entry 만 (search 위양성 차단)
- Archive 자동 제외 (졸업 학생 보관본 회상 안 함)
- 친절한 빈 결과 안내 ("철수 vs 김철수" 이름 변형 힌트)

**P16-T06: Insight 학생 디제스트 직접 연계**
- 학생 디제스트 합성 결과 존재 시 toggle 노출 (Insight.find("students:NAME"))
- "✨ 디제스트로 채우기" 보라 버튼 → curated 본문 사용
- "↩ 원본 entries 로 다시" toggle 로 양방향 전환
- synth_at·source_count 메타 노출
- 합성 결과 부재 시 graceful (toggle 미노출, 기본 자동 채움 작동)
- 4 BC 통합의 완성 — Insight 결과가 Output 양식 form 에 직접 흐름

### Spec (+93)

- spec/system/export_spec.rb (9)
- spec/system/generate_spec.rb (16)
- spec/system/generate_auto_fill_spec.rb (9)
- spec/system/memo_subject_spec.rb (11)
- spec/system/archive_spec.rb (9)
- spec/system/generate_digest_integration_spec.rb (7)
- spec/output/pdf_renderer_spec.rb (14)
- spec/output/docx_renderer_spec.rb (11)
- spec/output/font_config_spec.rb (6)
- 갱신: stage_1, stage_4b — NotImplementedError stub 폐기 → 실 binary 검증
- 1912 → 2005 examples (+93, +4.9%)

### v0.2.0 README "알려진 한계" 해결

- ~~PDF / DOCX 출력 — Prawn 한글 + caracal 별도 task~~ → **R4b-followup 완료**

### 알려진 한계 (다음 release 후보)

- Pretendard italic 변종 부재 (Regular 로 fallback, 시각 효과 약함)
- Wikilinks `[[link]]` PDF 렌더 미지원 (plain text)
- Generate form 의 "🌱 새 디제스트 합성" 버튼 미지원 (LLM 비동기 처리 필요)
- Domain::Note / NotesController 실제 코드 삭제 (Migration 011) — 호환성 유지로 보류

## [0.2.0] - 2026-05-12 — Phase R 모듈형 재구조화 (Bounded Context 4 layer)

## [0.2.0] - 2026-05-12 — Phase R 모듈형 재구조화 (Bounded Context 4 layer)

비전 D ("쓰기·정리·통찰·출력") 4 단계 와 1:1 대응하는 4 Bounded Context 모듈형 구조로
전면 재구조화. 11 commits / 5 Stage (W33-W40) / 1912 spec / 0 failure / 0 arch 위반.

### 🏗️ 새 4 Bounded Context 아키텍처 (ADR-019)

```
core ──→ capture ──→ knowledge ──→ insight ──→ output
            (D.1)       (D.2)        (D.3)       (D.4)
```

각 BC 는 Façade (외부 API) + Domain (불변 객체) + Repo (영속화) 3 계층.
`bin/sowing-arch-check --strict` 가 모든 commit 에서 의존 그래프 검증.

### Stage 1 (W33) — Bounded Context 골격
- `lib/sowing/{capture,knowledge,insight,output}.rb` Façade entry 파일
- `bin/sowing-arch-check` 의존 그래프 검증 executable
- `lib/sowing/infrastructure/` → `lib/sowing/core/` rename (13 파일, namespace 갱신)

### Stage 2 (W34) — Capture Bounded Context
- `Sowing::Capture::Item` 도메인 (옛 Memo 의 후신 + subject 4축, ADR-016)
- `Capture::ItemRepo` 영속화 어댑터
- `Sowing::Capture` Façade — `create_item / find / recent`
- Strangler Fig — `POST /memos` → `Capture.create_item` 위임 (`UseCases::CreateMemo` 미경유)
- **Migration 008** — entries.subject TEXT + CHECK ENUM (person/subject/document/identity)

### Stage 3 (W35-36) — Knowledge Bounded Context
- `Sowing::Knowledge::Record` (Note + Record 흡수 superset, ADR-015)
  - source (Note 흡수) + category (자유 텍스트) + subject (4축) + promoted_from
- `Sowing::Knowledge::Plan` (period 5종 + done 토글, 옛 Domain::Plan 의 후신)
- `Knowledge::RecordRepo` + `Knowledge::PlanRepo` 영속화
- `Sowing::Knowledge` Façade — `create_record / create_plan / find / recent_records / recent_plans`
- **Migration 009** — entries.archived_at + archive_reason (ADR-017 Archive 메타)
- `Knowledge.archive(id, reason:)` / `unarchive` / `archived` — 일상 회상 자동 제외
- 부수 회귀 수정: `IndexRepo.validate_mode!` 에 `:plan` 누락 분 (migration 007 잔여)

### Stage 4a (W37) — Insight Bounded Context
- `Sowing::Insight::Synthesis` 통합 도메인 (18 type, status :pending 단일)
- `Insight::SynthesisRepo` — `.sowing/synth/{type}/{slug}.md` 파일 영속화
- `Sowing::Insight` Façade — `generate / pending / find / accept / reject`
- `USE_CASE_DISPATCH` (18 type → 14 옛 `UseCases::Synthesize*` 매핑) — Strangler Fig
- `accept` cross-BC: `Knowledge.create_record` 호출 (insight → knowledge 의존)

### Stage 4b (W38-39) — Output Bounded Context (Markdown MVP)
- `Sowing::Output::Template` ERB 단위 (stdlib only, 외부 gem 0)
- `Output::TemplateRegistry` — user override `>` system default (게이트 #4 a)
- 5 default ERB templates (`templates/exports/`):
  - student_record (생기부) · consultation (상담부) · meeting_minutes (회의록)
  - project_proposal (사업계획서) · budget_request (예산요구서)
- `Sowing::Output.generate(type:, format:, write_to:, **locals)` Façade
- PDF/DOCX 는 R4b-followup 으로 분리 (Prawn 한글 폰트 + caracal 별도 작업)

### Stage 5 (W40) — Note 폐지 마이그레이션 + 본 릴리스
- **Migration 010** — entries.mode='note' → 'record' 데이터 변환 (ADR-015)
  - path 자동 재작성: `20_Notes/{cat}/x.md` → `30_Records/{YYYY}/{cat}/x.md`
  - 멱등 — note 행 0 이면 no-op, 안전 재실행
- **`rake vault:migrate_notes_to_records`** — 실제 파일 시스템 이동 task
- 옛 `Domain::Note` / `UseCases::CreateNote` / `NotesController` 은 deprecated
  (Phase 16 에서 코드 삭제 예정 — 본 릴리스에서는 호환성 유지)

### ADR 추가 (5건)
- ADR-015 Note 폐지 (Knowledge::Record 가 superset)
- ADR-016 Subject 4축 (person / subject / document / identity)
- ADR-017 Archive 메타 (영구 삭제 0, 일상 회상 제외)
- ADR-018 Template-based Export 5종
- ADR-019 4 Bounded Context 의존 그래프

### Spec 추가 / 갱신
- 1674 → 1912 examples (+238)
- `spec/refactoring/stage_{1,2,3,4a,4b,5}_*_spec.rb` — Phase 별 통합 검증
- `spec/{capture,knowledge,insight,output}/` — BC 단위 도메인 spec

### 알려진 한계 (Phase 16 follow-up)
- PDF / DOCX 출력 — Prawn 한글 + caracal 별도 task
- `Domain::Note` 클래스 실제 삭제 — 호환성 유지 위해 본 릴리스에서는 보존
- `Migration 011` (mode CHECK 에서 'note' 제거) — 코드 삭제와 동기화 후 진행
- `UseCases::CreateMemo` 잔여 사용처 1건 (`MCP::Tools::CreateMemo`) — 별도 strangulation

## [0.1.8] - 2026-05-11 — Plan: 같은 날짜 여러 개 + 오전/오후 grouping (W32)

사용자 피드백 반영. v0.1.7 의 "1 파일 1 plan overwrite" 모델을 폐기하고
같은 날짜에 여러 plan 가능 + 오전/오후 자동 분류.

**Path 규칙 변경**:
- daily/weekly/monthly: `{plan_date}-{HHmm}-{ULID끝4}.md`
  예: `40_Plans/daily/2026-05-11-0930-X4F2.md`
- project/semester: `{plan_date}-{ULID끝4}.md` (시간 prefix 불필요)
- 각 plan 이 unique path → UNIQUE 충돌 0
- ULID 끝 4자리 = Crockford Base32 (같은 분 충돌 0)

**Grouping (PlansController#index)**:
- daily/weekly/monthly: 날짜별 + 오전/오후 분리
  - 오전: `created_at.hour < 12`
  - 오후: `created_at.hour >= 12`
- project/semester: grouping 없이 단일 리스트 (시간 의미 약함)
- 날짜 역순 (최신 위)
- 각 group 안 plan 도 시간 오름차순

**UI (views/plans/index.erb)**:
- `📅 {date} (총 N건)` 날짜 헤더 (border-top 분리)
- `🌅 오전 (N건)` amber 그라디언트 카드
- `🌆 오후 (N건)` blue/purple 그라디언트 카드
- 시각 표시 (HH:MM, 날짜 중복 제거)
- 옵시디언 호환 안내 갱신 (새 path 패턴 + 자동 분류 명시)

**v0.1.7 overwrite 로직 보존**:
- `upsert_index` 의 'same path 다른 id 시 delete' 로직 그대로
- W32 부터 unique path 라 거의 실행 안 됨
- 마이그레이션 미적용·기존 파일과의 정합성 안전망

**Spec**:
- spec/system/plans_multi_per_day_spec.rb 신규 (11 case):
  - Path 규칙 검증 (2): daily/weekly/monthly + project/semester
  - 같은 날짜 여러 plan UNIQUE 0 (2)
  - 오전/오후 grouping UI (5)
  - 날짜별 그룹 (1)
  - project 단일 리스트 (1)
- 기존 spec 3 path expectation 갱신 (정규식 매치)
- v0.1.7 'overwrite' spec → 'unique path' 의미로 변경
- 1663 → 1674 (+11), 0 failures

**ADR 영향**: 0 (도메인·라우트 unchanged)

**사용자 가치**:
- "오전엔 평가, 오후엔 면담" 식 자연스러운 일정 관리
- 같은 날짜 plan 충돌 0 → 폼 제출 시 항상 성공
- 옵시디언에서 파일명만 봐도 시간 인지 (HHmm prefix)

**파일 9**:
- plan_repo (resolve_path 패턴) + plans_controller (grouping helper) +
  view (grouping UI) + css (date-group + half-day) + spec × 4 + 캡쳐

## [0.1.7] - 2026-05-11 — Hotfix: Plan 같은 날짜 재제출 UNIQUE 충돌

**버그**: 같은 period+date (예: daily 2026-05-11) 의 plan 을 두 번째 제출 시
`Sequel::UniqueConstraintViolation: entries.path` 발생. 사용자가 "오늘 plan
하나 더" 시도 시 500 에러.

**원인**:
- PlanRepo.write 가 vault file 은 덮어쓰지만 (File.write)
- CreatePlan use case 가 매번 새 ULID 로 도메인 생성
- entries 테이블에 새 id 로 INSERT 시도 → path UNIQUE 위반

**Fix** (lib/sowing/repositories/plan_repo.rb#upsert_index):
- 같은 path 의 기존 entry 가 다른 id 라면 기존 row 먼저 delete
- 그 후 새 id 로 upsert (file 은 이미 덮어써졌으니 entries 도 정합)
- 같은 id 재제출 (toggle 등) 은 기존 동작 그대로 (id update path)

**의도된 동작 (Overwrite semantics)**:
- 같은 period+date 는 1 파일 1 plan
- 두 번째 제출 = "수정" 으로 처리 (vault file 덮어쓰기, entries 새 id)
- 향후 W32 에서 사용자에게 "이미 plan 있음 — 수정으로 진입?" 안내 UI 가능

**Spec** (spec/system/plan_index_integration_spec.rb):
- '같은 path 새 ULID 제출 → UNIQUE 위반 0 + 기존 row 대체'
- '같은 id 재제출 (toggle) 은 기존 동작 그대로'
- 10 → 12 case, 0 failures

**ADR 영향**: 0 (도메인·라우트·UI 변경 없음)

**파일 2**:
- lib/sowing/repositories/plan_repo.rb (10 라인 추가)
- spec/system/plan_index_integration_spec.rb (regression test)

## [0.1.6] - 2026-05-11 — Phase 14 W31 PoC: 모바일 햄버거 + 터치 chip 크기

v0.1.5 의 단축키 (W30) 에 이어 세 번째 Phase 14 PoC. 모바일 viewport (≤768px)
에서 햄버거 메뉴 + 모든 chip 의 터치 영역 확대.

**JS 0 햄버거 패턴**:
- `<input type="checkbox" id="nav_mobile_toggle">` (hidden)
- `<label for="nav_mobile_toggle">` 햄버거 버튼 (☰ / ✕)
- `.nav-mobile-toggle:checked ~ .nav-v2 { display: flex }` 로 CSS-only 토글
- Sowing 의 'JS 의존성 최소화' 원칙 (CLAUDE.md) 일관

**모바일 변화 (@media max-width 768px)**:
- nav-v2: vertical drawer (`position: absolute`), `box-shadow` + `border-top`
- 1급 메뉴: padding 0.8em + min-height 44px (HIG 권장)
- dropdown panel: `position: static` (drawer 안에서 inline 펼침, 화면 밖 X)
- 햄버거 버튼: min-width/height 44px

**터치 chip 크기**:
- `.quick-modal__chip` / `.quick-modal__emotion-chip` /
  `.view-recent__chip` / `.plans__chip` / `.synth-llm-toggle__model select`
  모두 min-height 40px + padding 확대
- emotion chip min-width 64px (얇은 chip 도 탭 영역)
- stats / view-recent / plans 아이템 패딩 보충
- body 폰트 0.96rem

**ADR 영향**: 0
- ADR-001 / ADR-009 / ADR-013 / ADR-014 모두 무관
- 모든 변경 CSS + 1 input markup — 데이터·도메인·라우트 0

**Spec & 검증**:
- spec/system/mobile_ux_spec.rb 신규 (13 case)
- HTML markup 4 / CSS 햄버거 4 / CSS chip 3 / 회귀 2
- 1648 → 1661 (+13), 0 failures
- standardrb clean

**캡쳐 한계 안내**:
- Chrome headless `--window-size 375` 만으로는 viewport media query 100% 일치 X
- 실제 모바일 기기 또는 Chrome DevTools 모바일 에뮬레이션으로 확인 권장
- Markup + spec 으로 동작 보장 (햄버거 토글 = 순수 CSS, timing 이슈 0)

**파일 5**:
- views/layouts + public/css + spec + 캡쳐 × 2

**사용자 가치**:
- 출퇴근 중 폰으로 메모 즉시 가능
- 모바일 nav 5+1 동사 메뉴 접근성 보장
- 교실 책상에 폰 둔 채 chip 정확 탭

다음 단계:
- 다국어 (r18n 영문) — 해외 베타 가능성
- 또는 베타 인터뷰 (2026-08) 후 Phase 14 본격 진입

## [0.1.5] - 2026-05-11 — Phase 14 W30 PoC: 단축키 사용자 정의

v0.1.4 의 다크 모드 (W29) 에 이어 두 번째 Phase 14 PoC. 글로벌 단축키의
마지막 한 글자만 사용자 정의 가능 (modifier 고정으로 충돌 방지).

**Settings 신규** (DEFAULTS):
- shortcut_quick_memo: "m" (default — ⌘⇧M)
- shortcut_quick_search: "k" (default — ⌘K)

**설계 — modifier 고정 + 1 글자만**:
- modifier (Cmd / Ctrl + Shift) 자유 입력은 OS·브라우저 충돌 검증 부담 큼
- '⌘⇧M' 의 'M' 만 바꾸면 핵심 needs 90% 커버
- 안전 charset (a-z) 만 — 숫자·특수문자·다국어는 default 폴백 (sanitize 보안)

**구현**:
- POST `/settings/shortcuts` + `sanitize_shortcut_key` helper (helpers do)
- Layout 에 `window.SOWING_SHORTCUTS = {quick_memo, quick_search}` JSON 주입
- Settings.load rescue → default 폴백 (graceful)
- quick_memo_controller.js / quick_search_controller.js — hardcoded 'm'/'k'
  → `window.SOWING_SHORTCUTS?.quick_memo || "m"` 패턴 (JS-side fallback 도 명시)

**Settings UI**:
- ⌨ 단축키 섹션 — 두 줄 inline (라벨 + ⌘⇧ prefix + 1글자 input + 기본값)
- HTML5 pattern="[a-zA-Z]" + maxlength=1 — 클라이언트 1차 검증
- `.settings__shortcut*` 4 sub-class (monospace + uppercase + ⌘⇧ chip)

**사용자 가치**:
- 옵시디언 이미 ⌘⇧M 사용 중 → Sowing 메모를 ⌘⇧J 로 회피
- vim 사용자 → ⌘P 같은 친숙한 검색 패턴
- 한국어 IME 입력 중 충돌 시 다른 글자로 회피

**Spec**:
- spec/system/shortcuts_spec.rb 신규 (15 case)
- DEFAULTS / POST sanitize 4종 / Layout 주입 3종 / Settings UI 3종 / JS 자산 3종
- 1633 → 1648 (+15), 0 failures

**ADR 영향**: 0
- ADR-001 (SoT) / ADR-009 (로컬-first) / ADR-013 (자율 mutation 0) / ADR-014 (동사 IA) 모두 영향 없음
- client-side + Settings 키 2개 추가만

**파일 8**:
- settings + settings_controller + layout + view + 2 JS controller + CSS + spec

## [0.1.4] - 2026-05-11 — Phase 14 PoC 진입: 다크 모드 + 베타 인터뷰 가이드

Phase 13 (v0.1.2/v0.1.3) 출시 후 Phase 14 의 첫 PoC. 베타 인터뷰 결과 무관하게
사전 가능한 영역 — **다크 모드** + **베타 인터뷰 가이드 문서화**.

**다크 모드 (W29 PoC)**:
- 3 테마: `auto` (default, OS 자동) / `light` (강제) / `dark` (강제)
- CSS variable override 패턴 — 8개 토큰 (bg/card-bg/text/muted/border/code-bg/shadow/input-bg)
- `:root[data-theme="dark"]` 강제 + `@media (prefers-color-scheme: dark)` auto
- Hard-coded `background: white` 37 occurrence → `var(--color-card-bg)` 일괄 (모든 카드 자동 다크 적응)
- Settings 페이지에 '🌗 테마' 라디오 3종
- `<html data-theme>` + `<meta color-scheme>` 동적 적용
- Settings 손상 시 auto 폴백 (graceful)
- ADR 영향 0 — 시각 토큰만 변경, 도메인·정체성 그대로
- 캡쳐: docs/screenshots/25-dashboard-dark.png, 26-settings-dark.png

**베타 인터뷰 가이드 (Phase 13 후속 측정 도구)**:
- `docs/BETA_PHASE13_INTERVIEW.md` (242 lines, 9 섹션)
- 정량 5종 (첫 메모 시간 / 1주차 이탈률 / nav hover / 합성기 사용률 / mode 의식)
- 인터뷰 30분 7 Stage (Warm-up + Nav + 글쓰기 + Plan + 자기거울 + 통합 + 정량)
- 의사결정 트리 4 분기
- 진행자 cheat sheet (질문 패턴 / 침묵 활용 / 데이터 동의)
- 일정 제안 (모집 → 3개월 사용 → 인터뷰 → Phase 14 결정)

**문서 갱신**:
- `docs/BETA_GUIDE.md` 헤더에 v0.1.3 + Phase 13 인터뷰 안내 박스
- `README.md` 문서 테이블에 BETA_PHASE13_INTERVIEW + REDESIGN_IA 추가

**Spec & 검증**:
- 1617 → 1633 (+16 다크 모드 신규)
- 0 failures
- standardrb clean

**파일 (11 modified/new)**:
- 다크 모드: settings/settings_controller/layout/css/spec + 캡쳐 × 2
- 인터뷰 가이드: BETA_PHASE13_INTERVIEW.md + BETA_GUIDE.md + README.md

다음 단계 (Phase 14 후속):
- 단축키 사용자 정의 PoC
- 모바일 웹 UX 개선 (햄버거 메뉴 + 터치 chip)
- 다국어 (r18n 영문 추가)
- 베타 인터뷰 결과 (2026-08) 반영

## [0.1.3] - 2026-05-11 — Plan IndexRepo 통합 (W27-T03)

v0.1.2 Phase 13 의 후속 — Plan mode (W27-T01·T02) 를 entries 테이블에 통합해
recent_across / /view/recent / 검색 모두 plan 도 1급 시민으로 인덱싱.

**Migration 007** (db/migrations/007_add_plan_to_entries_check.rb):
- entries.mode CHECK 제약에 'plan' 추가
- SQLite CHECK 변경은 ALTER TABLE 불가 → table recreate 패턴
  (entries_v2 만들기 → INSERT SELECT → DROP entries → RENAME)
- 인덱스 3개 재생성 (mode, created_at, category)
- entries_fts 가상 테이블 영향 없음 (트리거 0, IndexRepo 명시 sync)
- down 마이그레이션 안전망 — plan entries 있으면 거부

**PlanRepo 확장**:
- initialize 에 index_repo 인자 추가 (lazy 생성)
- write / toggle_done 모두 IndexRepo.upsert 자동 호출
- Sequel::CheckConstraintViolation rescue — migration 미적용 시 graceful

**ViewController**:
- view_mode_label / view_mode_path 에 :plan → '🗓 계획' / `/plans/{id}` 추가
- @selected_mode allowlist 에 'plan' 추가
- view_body_excerpt — VaultRepo.read 대신 직접 파일 읽기 (mode-agnostic)

**UI**:
- /view/recent 의 mode chip 4종 (memo/note/record/plan)
- .view-recent__item--plan / __badge--plan (purple, Plan mode identity 일관)

**Spec**:
- spec/system/plan_index_integration_spec.rb 신규 (10 case)
- plans_spec.rb / plans_w27t02_spec.rb — entries cleanup 추가 (격리)
- 1607 → 1617 (+10), 0 failures

**사용자 가치**:
- "이번 주 작성한 모든 것" 한 화면 (메모 + 필기 + 기록 + **계획**)
- 카테고리 × 연도 매트릭스에 plan 도 등장 가능 (향후)
- FTS5 검색이 plan body 도 인덱싱

**파일 8**:
- db/migrations/007 + plan_repo + view_controller + view/recent + css + spec × 3

## [0.1.2] - 2026-05-11 — Phase 13: 동사 중심 IA + Plan mode + 17번째 합성기 자기 거울

**가장 큰 변화** — 평면 nav 10항목 → 5+1 동사 중심 (글쓰기·쓴 글 보기·쓸 글 계획·자기 거울 + 홈·설정). 4번째 1급 mode "계획" 신설. 17번째 합성기 "자기 거울 (5축)" + 대시보드 위젯 + 매일 자동 생성. ADR-014 정식 채택.

**계기**: `docs/gb-docs.md` (김교수 "지독한 기록" 영상 transcript) 비교 분석 → 평면 nav 가 신규 사용자 진입장벽. 명사 (메모/필기/기록) 노출이 사용자 동사 (적다/보다/계획하다/회고하다) 와 어긋남.

**ADR-014 정식 채택**: 명사 mode (저장 단위 — 메모/필기/기록/계획/합성) 와 동사 mode (사용자 의도 — 글쓰기/보기/계획/회고) 두 계층 명시 분리. 마크다운 SoT (ADR-001) 영향 0. 자세한 결정: [docs/DECISIONS.md ADR-014](docs/DECISIONS.md#adr-014).

**W25 — Nav 재설계 (2 작업)**:
- W25-T01 `<details>` dropdown 5+1 nav (JS 0)
- W25-T02 1회 변경 안내 모달 (`Settings.ia_v2_seen_at`)

**W26 — 글쓰기 + 쓴 글 보기 (3 작업)**:
- W26-T01 빠른 메모 5 subtype (책/강의/감정/학생/일반) — 도메인 변경 0, client-side body 결합 + 자동 태그
- W26-T02 음성 입력 PoC (Web Speech API ko-KR, Whisper.cpp 로컬 W26-T02b 예정)
- W26-T03 `/view/recent` 통합 시간순 페이지 (메모/필기/기록 합본 + mode/카테고리 chip 필터)

**W27 — 쓸 글 계획 (2 작업)**:
- W27-T01 `Sowing::Domain::Plan` + `PlanRepo` + `40_Plans/` + CRUD UI
- W27-T02 5 period (daily/weekly/monthly/project/semester) + 대시보드 "오늘 할 일" 위젯

**W28 — 자기 거울 (3 작업)**:
- W28-T01 17번째 합성기 `SynthesizeSelfMirror` — 5축 (지성·감정·습관·관계·에너지)
- W28-T02 대시보드 "오늘의 자기" 위젯 (opt-in: `daily_mirror_enabled`)
- W28-T03 자동 매일 생성 hook (대시보드 진입 시) — 결과는 검토 대기 폴더 (ADR-013 호환)

**기존 URL 100% 호환**: `/memos`, `/notes`, `/records`, `/tags`, `/search`, `/synth`, `/graph`, `/templates`, `/settings` 모두 그대로 작동. 신규 동사 라우트 `/write`, `/view`, `/plan`, `/mirror` 는 추가 진입점.

**ADR-013 자율 mutation 0 유지**:
- 자동 생성 결과는 `.sowing/synth/self-mirror/` 검토 대기 폴더에만
- 30_Records/회고/ 로의 정식 이동은 사용자 수락 클릭으로만
- audit log 에 actor=agent 로 기록
- `daily_mirror_enabled = true` 자체가 매일 자동 생성 명시 동의

**Spec & 캡쳐**:
- 1430 → 1607 (+177 신규 spec)
- 0 failures
- standardrb clean
- docs/screenshots/ 13 → 24 (+11 신규 캡쳐)

**문서**:
- `docs/USER_GUIDE.md` 전면 갱신 — 14 섹션 (이전 11 섹션), Plan mode + 자기 거울 신규 §9·§10
- `docs/REDESIGN_IA.md` (Phase 13 설계 원본, W25 commit)
- `docs/DECISIONS.md` ADR-014 정식 추가
- `ROADMAP.md` Phase 13 항목 (12 작업 — T03 일부 deferred)

**효과 목표 (베타 인터뷰로 측정 예정)**:
- 신규 사용자 첫 메모까지 시간 < 30초 (현재 ~2분)
- 1주차 이탈률 < 20% (현재 ~40% 예상)
- Nav hover 평균 < 1.5회 (현재 3.2)
- 합성기 월 사용률 > 60% (현재 ~30%)

**파일 (10 commit, 누적 ~80개 파일)**:
- 핵심 코드: ViewController / PlansController / Plan domain / PlanRepo / CreatePlan / SynthesizeSelfMirror
- UI: nav v2 + 9 신규 partial/page + 50+ CSS sub-class
- Spec: 7 신규 spec 파일 + 7 기존 spec 갱신

## [0.1.1] - 2026-05-11 — LLM 통합 강화 (.env 자동 로딩 + UI 모드 toggle + 모델 선택)

v0.1.0 의 LLM 합성기 인프라를 사용성 측면으로 끌어올림. 사용자가 셸에서 `export`
없이 `.env` 만 만들면 즉시 LLM 모드 사용 가능. UI 의 4 LLM-capable 합성기 폼
(parent-patterns / self-patterns / event-causality / contradictions) 에 모드
체크박스 + 모델 드롭다운 + 1건당 비용 추정 표시.

**.env 자동 로딩 (외부 gem 0)**:
- `Sowing::Infrastructure::Dotenv` 신규 — 자체 ~50줄 파서.
  - 형식: `KEY=value`, `KEY="..."`, `KEY='...'`, `export KEY=val`, 인라인 주석, 빈 값
  - 우선순위 (강 → 약): 시스템 ENV > `.env.local` > `.env`
  - **시스템 ENV 가 명시 export 한 값은 절대 덮지 않음** — 운영 환경 안전.
  - 변수 보간 (`${VAR}`) / 다중라인 / 명령 치환은 의도적 미지원 (단순함 우선).
- `Sowing.boot!` 의 가장 앞 단계로 `boot_dotenv!` 추가 — 이후 단계 (Paths,
  DB 등) 가 ENV 를 안전하게 읽음.
- `.env.example` 템플릿 신규 — `ANTHROPIC_API_KEY`, `SOWING_PORT`, `SOWING_ENV`
  주석 + 우선순위 안내.
- 기존 `.gitignore` 의 `.env` / `.env.local` 패턴 그대로 유지 — 비밀 누출 0.

**Anthropic backend fix**:
- `DEFAULT_MODEL` 가짜 모델 ID `claude-haiku-4-20260114` (존재 안 함) →
  실제 존재하는 `claude-haiku-4-5-20251001` (Claude Haiku 4.5) 로 교정.
- v0.1.0 의 LLM 모드 기본 호출은 모델 ID 오류로 실제 동작 불가 상태였음.
  Anthropic Models API 로 가용 모델 확인 후 fix.

**UI LLM 모드 toggle (4 type)**:
- 신규 partial `views/synth/_llm_toggle.erb` — 4 폼 (parent-patterns,
  self-patterns, event-causality, contradictions) 에서 공통 사용.
- ENV 키 유무에 따라 두 가지 분기:
  - **키 설정됨**: `🌱 LLM 모드` 체크박스 + 모델 드롭다운 + 비용 안내
  - **키 미설정**: `.env` 설정 안내 + 결정적 fallback 동작 안내
- `SynthController` helpers: `llm_available?`, `llm_backend_from_params`,
  `resolve_llm_model` — backend 주입 분기 + 폼 model > ENV > DEFAULT 우선순위.
- `:has(input:checked)` CSS-only 활성화 — 체크 안 하면 모델 select 흐릿.
  JS 추가 의존성 0.

**모델 선택 드롭다운 (3 모델 카탈로그)**:
- `Anthropic::MODELS` 상수 — 모델별 메타 (label, tier, in/out per Mtok, speed):
  - `claude-haiku-4-5-20251001` (Haiku 4.5) — $1/$5 per Mtok, 2~5s, **default**
  - `claude-sonnet-4-5-20250929` (Sonnet 4.5) — $3/$15, 5~10s
  - `claude-opus-4-7` (Opus 4.7) — $15/$75, 15~30s
- `Anthropic.estimated_cost_per_synth(model)` — 합성 1건당 USD 추정 (input
  ~3K + output ~1K tokens 가정). UI 에 `≈ $0.0080 / 합성 1건` 형식으로 표시.
- `Anthropic.valid_model?` allowlist 검증 — 카탈로그에 없는 model 문자열은
  무시 → DEFAULT 폴백. 폼/ENV 에서 임의 문자열 주입 시도 시 안전.
- `ANTHROPIC_MODEL` ENV 변수도 인식 — 운영자 기본값 설정 가능.

**Spec (LLM 통합 검증, 1430 → 1440)**:
- `spec/infrastructure/dotenv_spec.rb` — 10 case (KEY=value, 따옴표, 주석,
  export, 빈 값, 시스템 ENV 우선, .env.local 우선, 잘못된 키 무시, 로딩 결과
  배열, 빈 디렉토리)
- `spec/system/synth_llm_toggle_spec.rb` — 10 case:
  - 표시 분기: 키 미설정 시 안내 + 키 설정 시 체크박스/드롭다운/Haiku/Sonnet/Opus/비용
  - backend 주입: 키+llm=1 → Anthropic, 키만 → nil, llm=1만 → nil, ENV 모델, 폼 우선, allowlist 폴백
  - 비용 추정: Haiku < Sonnet < Opus 단조증가 + unknown nil

**검증 (실 서버 + LLM 호출)**:
- self-patterns LLM 모드 재시도 → ✅ 3271B 출력 (이전 v0.1.0 출시 시
  DEFAULT_MODEL 가짜로 LLM batch 실패해 결정적 fallback 만 시연됐던 항목 회복).
- parent-patterns / event-causality / contradictions 모두 LLM 모드 batch 시연
  성공 — 4/4 합성기 `synth_model: Anthropic` frontmatter + 결정적 fallback
  trailer 없음 + audit log `actor: agent` 정상.
- 1440 spec / 0 failures.

**ADR 영향**:
- ADR-013 (자율 mutation 0): UI 체크박스 = 사용자 명시 클릭. 비용 표시로
  사용자가 "지금 합성 1건 = $0.0080" 인지하고 누름 — 동의 강화.
- ADR-009 (LLM opt-in): ENV 키 + UI 체크 둘 다 명시적. 안전 fallback.

**파일 (12)**:
```
lib/sowing/infrastructure/dotenv.rb            (신규, ~75 lines)
lib/sowing/eval/backends/anthropic.rb          (MODELS 카탈로그 + DEFAULT_MODEL fix + 비용/allowlist)
lib/sowing/controllers/synth_controller.rb     (5 helpers + 4 routes 에 llm_backend 주입)
config/application.rb                          (boot_dotenv! 추가)
views/synth/_llm_toggle.erb                    (신규 partial)
views/synth/index.erb                          (4 폼에 partial 삽입)
public/css/application.css                     (.synth-llm-toggle 스타일)
spec/infrastructure/dotenv_spec.rb             (신규, 10 case)
spec/system/synth_llm_toggle_spec.rb           (신규, 10 case)
.env.example                                   (신규 가이드 템플릿)
CHANGELOG.md                                   (이 항목)
lib/sowing/version.rb                          (0.1.0 → 0.1.1)
```

### 확장 합성기 #11 + #12 — 학습 진척 추이 + 사건 인과 추론 (2026-05-11)

/synth 16 type 완성. 두 신규 합성기는 *시계열 분석* 강화 — 페이스/누적 곡선/
before-after 비교.

**#11 SynthesizeLearningProgress (학습 진척 추이)**:
- vs 기존 #6 SynthesizeLessonSeries (단원 차시 timeline):
  - LessonSeries: 차시 timeline + 단원 종료 감지 + 학생 반응
  - **#11**: **차시 간격 페이스 분석** + 누적 곡선 + **학습 활동 분포** + 진행 상태 자동 판정 (active/dormant/ended)
- 입력: keyword + 6개월 window
- 결정적 출력:
  - 진행 상태 (마지막 차시 후 30일 → dormant, 60일 → ended)
  - 페이스 분석: 평균/최대/최소 간격, **일정 비율** (평균 ±3일 안 차시 비율)
  - 학습 활동 분포: 모드별 + 카테고리별
  - 학습 cohort: 자주 등장한 학생 top 8 (entity_mentions 활용)
  - 누적 차시 곡선 (주 단위 text bar chart)
  - 차시 timeline (시간순)
- LLM 4 섹션: 학습 페이스 평가 / 활동 균형 / 학습 cohort 패턴 / 다음 차시 우선순위
- 저장: `vault/.sowing/synth/learning-progress/{keyword}.md`
- frontmatter 11키 (synth_keyword + status + avg_interval_days + days_since_last)
- accept_category=학습기록

**#12 SynthesizeEventCausality (사건 인과 추론)**:
- vs 기존 #3 ExtractTrainingApplications (연수→적용 키워드 매칭):
  - #3: 연수 노트 1건 → 후속 키워드 매칭
  - **#12**: 임의 *사건 키워드* → before/after **통계 변화** (톤·학생·카테고리·빈도)
- ⚠ **인과 단정 절대 거부** (ADR-013):
  - 합성기는 *상관 패턴* 만 표시 — "X 가 Y 의 원인" 표현 금지
  - trailer 명시: **"상관 = 인과 아님"**
  - LLM prompt 도 "원인일 가능성", "관련일 수도" 톤 강조
- 입력: event_keyword + window_days (default 30) + event_at (옵션, nil 이면 첫 등장 자동)
- 결정적 출력:
  - 사건 등장 timeline (title + body 매칭, 상위 10)
  - **Before vs After 비교 표**:
    - 작성 entries / 주당 빈도
    - 긍정·부정 신호어 (Phase 12 LessonPattern 부정 윈도 5자 필터 재사용)
    - 학생 mention 수 + 변화 화살표 (↑/↓)
  - 새로 등장 학생 (Before 에 없던) / 등장 멈춘 학생
  - 새 카테고리 등장
  - 카테고리 분포 (Before/After top 5)
- LLM 4 섹션: 관찰된 변화 / 가능한 상관 패턴 / 본문 명시 사건 / 다음 검증 제안
- 저장: `vault/.sowing/synth/event-causality/{keyword}.md`
- frontmatter 11키 (synth_event_keyword + event_at + window_days + before/after counts + new_student_count)
- accept_category=분석회고

SynthController::SYNTH_TYPES 16 type 완성:
- 기존 14 + learning-progress (📈) + event-causality (🎯)
- 새 라우트:
  - POST /synth/learning-progress/:slug/generate (keyword)
  - POST /synth/event-causality/:slug/generate (event_keyword + window_days + event_at)

views/synth/index.erb:
- 두 신규 generate 폼 + JS slug 핸들러
- event-causality 폼은 ⚠ "상관 = 인과 아님" 강조 hint

bin/sowing-doctor:
- Phase 12 use case 진단에 #11, #12 추가
- 16 type 디렉토리 카운트

검증:
- spec 17 신규
  - synthesize_learning_progress_spec 8 (결정적 4 + 가드 2 + LLM 2)
  - synthesize_event_causality_spec 9 (결정적 4 + 가드 3 + LLM 2)
- 회귀: 1400 → 1417 (+17), 0 fail
- standardrb clean
- doctor: 16 type 모두 ✅

핵심 디자인 결정:
- #11 의 "진행 상태 자동 판정" — 차시 간격 통계 기반 (단정 X, 통계 표시 only)
- #12 의 "상관 ≠ 인과" 의식적 강조 — view·trailer·LLM prompt 모두 인과 단정 거부
- 두 합성기 모두 전체 vault 시계열 분석 — Phase 11 W17-T01 entity_mentions 인프라 활용

### 확장 합성기 #9 + #10 — 학부모 상담 패턴 + 자기 회고 패턴 (2026-05-11)

기존 12 합성기 외 **두 신규 메타-합성기** 추가. /synth 14 type 완성.

**#9 SynthesizeParentPatterns — 학부모 상담 패턴 (학급 전체)**:
- vs 기존 #1 SynthesizeParentConsultation:
  - #1: 학생 *1명* + 면담 *준비* 자료
  - #9: 학급 *전체* + 학기 *상담 패턴* 분석
- 입력: 상담 카테고리 records + meetings notes + 6개월 window
- 결정적 출력:
  - 학생별 상담 빈도 (entity_mentions ⨝ entities, type=student)
  - 공통 토픽 키워드 (한국어 어절 + 조사 제거 + STOPWORDS — 학부모/면담/상담 등)
  - **미상담 학생 명단** (Settings.class_roster vs consulted set)
  - 학기 상담 timeline (시간순 인용)
- LLM 출력 4 섹션: 상담 흐름 / 가족 환경 패턴 / 학습 환경 패턴 / 다음 학기 우선 면담 후보 (강요 X)
- 저장: `vault/.sowing/synth/parent-patterns/{semester_label}.md`
- frontmatter 11키 (synth_consulted_count + roster_size + unconsulted_count 포함)
- accept_category=상담회고

**#10 SynthesizeSelfPatterns — 자기 회고 패턴 (교사 자신, 메타-합성)**:
- 다른 합성기는 학생·수업·연수·학부모 등 *외부* 분석. 이건 *교사 본인* 분석
- 입력: 모든 entries (default 6개월 window)
- 결정적 출력:
  - 기본 통계 (모드/평균 문장 길이)
  - 작성 시간대 분포 (hour_counts, peak_hour, 막대 그래프)
  - 자주 다룬 카테고리 / 토픽 키워드 (top 15)
  - **톤 신호어 카운트** — POSITIVE 23종 (잘됐/보람/뿌듯 등) vs NEGATIVE 23종 (힘들/지친/막막 등). 부정 윈도 5자 필터 적용 (Phase 12 LessonPattern 패턴 재사용)
  - **최근 4주 vs 이전** 톤 비교 — 잠재적 burnout 시그널 단서
  - 작성 공백 (7일+ 연속 빈 날, 상위 5)
- LLM 출력 4 섹션: 시기별 톤 변화 / 자주 환기되는 주제 / 잠재적 burnout 시그널 (단정 거부, "특별한 시그널 없음" 솔직히 표기 가능) / 다음 학기 의도적 시도 후보
- 저장: `vault/.sowing/synth/self-patterns/{period_label}.md`
- frontmatter 11키 (synth_positive_count + negative_count + gap_count 포함)
- accept_category=자기회고

자율 판단 0 (ADR-013):
- #9 trailer "원자료 — 면담 자리에서 교사 직접 판단·맥락 우선"
- #10 trailer "단정 거부: '교사가 지쳤다' X → '부정 신호어 N건' O. 해석은 본인이"
- LLM prompt 도 단정 금지 강조

SynthController::SYNTH_TYPES 14 type:
- 기존 12 + parent-patterns (👨‍👩‍👧, 학부모 상담 패턴 (학급)) + self-patterns (🪞, 자기 회고 패턴)
- 새 generate route: POST /synth/parent-patterns/:slug/generate (semester_label),
  POST /synth/self-patterns/:slug/generate (period_label)

views/synth/index.erb:
- parent-patterns / self-patterns generate 폼 (semester_label 또는 period_label
  + since/until + "전체 기간 (30년)" preset 버튼)
- JS 핸들러: slug 채우기 (인풋 → URL escape → form.action)

bin/sowing-doctor:
- Phase 12 진단 섹션에 두 use case 추가 (확장 #9, #10)
- 14 type 디렉토리 카운트

검증:
- spec 17 신규
  - synthesize_parent_patterns_spec 9 (결정적 5 + 가드 2 + LLM 2)
  - synthesize_self_patterns_spec 8 (결정적 5 + 가드 1 + LLM 2)
- 회귀: 1383 → 1400 (+17), 0 fail
- standardrb clean
- doctor: 14 type 모두 ✅

핵심 디자인 결정:
- #9 의 "미상담 학생 명단" — class_roster Settings 활용 (Phase 11 W17-T03 인프라 재사용)
- #10 의 "burnout 시그널" — 단정 거부 톤 의식적 강조. "지쳤어요" 대신 "최근 4주간 부정 표현 N건". 사용자가 데이터 보고 본인이 해석.
- 두 합성기 모두 LLM 모드도 *후보* 표현, 강요 0.

### 30년 시나리오 #4 — 위키링크 그래프 시각화 (2026-05-11)
**30년 시나리오 4종 모두 완성** (#1 OnThisDay + #2 timeline + #3 by-category + #5 합성기 window + 이번 #4 graph). 위키링크 그래프 인프라 (W3, links 테이블) 위에 *시각화만* 추가.

- **`IndexRepo#graph_data(mode_in:, category_in:, since:, until_time:, max_nodes:)`**:
  - 노드 = entry, 엣지 = wikilink (target_id NULL 제외)
  - 결과: `{nodes, edges, truncated, total}` — internal links 만 (필터 안 양 끝 모두 포함)
  - 노드 메타: id/mode/title/category/year/inbound/outbound (degree 계산)
  - `max_nodes` 안전 가드 (default 300, controller 가 [10, 1000] clamp)
- **`Sowing::Controllers::GraphController`** 신규:
  - `GET /graph` — 페이지 (필터 폼 + SVG 컨테이너 + 범례)
  - `GET /api/graph_data` — JSON API (Stimulus controller fetch)
  - 노드에 `href` 자동 추가 (mode → memos/notes/records 라우팅)
  - read-only — vault·DB·audit 변경 0
- **`public/js/controllers/graph_controller.js`** — 자체 force-directed:
  - **외부 라이브러리 0** (D3·cytoscape 등 의존 안 함, CLAUDE.md 빌드 도구 0 원칙 준수)
  - 인라인 SVG + Verlet integration (척력 + spring + 중심 중력 + 마찰 0.85)
  - 200 노드 / 400 엣지에서 60fps 유지
  - 노드 색상: mode 별 hue (memo 30° / note 200° / record 140°) + 연도 명도 (오래됨=옅음, 최근=짙음)
  - 노드 크기: degree 기반 (5 ~ 15px)
  - 고립 노드 (inbound 0 + outbound 0) 점선 노란 외곽선
  - 인터랙션: hover → tooltip (제목·연도·연결 수), click → entry 상세, drag → 위치 고정
- **`views/graph/index.erb`**: 모드/카테고리 chip 필터 + 날짜 범위 + 최대 노드 슬라이더 + 범례 + 통계 (노드/엣지/truncated)
- **`views/layouts/application.erb`**: importmap 에 graph controller 등록 + nav "🕸 그래프" 링크
- **CSS**: `.graph-page__*` (필터/범례/stats/container) + `.graph-svg` (radial gradient 배경) + `.graph-tooltip`
- **spec 18 신규**:
  - `spec/repositories/index_repo_graph_spec.rb` 9 케이스 (기본/필터/max 가드/broken link/internal links)
  - `spec/system/graph_spec.rb` 9 케이스 (페이지/API JSON/기본 모드/href/필터/truncated/read-only ADR-013)
- 회귀: 1365 → 1383 (+18). lint clean.

**30년 시나리오 5종 모두 완성** — 코드 deliverable 완료. 사용자 vault 의 실제 데이터로 검증 가능. `/graph` 진입 시 force layout 자동 시작 → 클러스터·고립 entry·시간 흐름 시각화.

### 30년 시나리오 강화 — cross-year 탐색 4종 (2026-05-11)
**배경**: 사용자 의도 = "30년 누적 기록을 연도 무관 검색·연결·확인". 폴더 구조
변경 (`30_Records/{YYYY}/{cat}/` → 평면) 비용 분석 결과 옵시디언 호환·1336 spec
회귀·vault 마이그레이션 비용 큼 → **현재 폴더 구조 유지** + **앱 안에서 시간
무관 탐색 강화** 4 deliverable.

- **#1 "이날의 회고" 대시보드 위젯**:
  - `IndexRepo#on_this_day(month:, day:, exclude_year:, limit:)` — `SUBSTR(created_at, 6, 5) = 'MM-DD'` SQLite 쿼리
  - `DashboardController#compute_on_this_day` — 오늘 연도 제외, 최근 연도 desc, top 5
  - `views/dashboard/show.erb` — `<aside class="on-this-day">` 카드 (year + years_ago + title + category)
  - 매일 자연스러운 30년 환기 — 의식적 검색 0
- **#2 `/records/timeline` — 평면 cross-year 뷰**:
  - `IndexRepo#list_records_flat(category_in:, q:, since:, until_time:, order:, limit:, offset:)` + `count_records_flat` (FTS5 조인)
  - `RecordsController#get "/records/timeline"` (`:id` 라우트보다 먼저 배치)
  - `views/records/timeline.erb` — 다중 카테고리 chip + 키워드 + 날짜 범위 + asc/desc 정렬, 연도 헤더 자동 삽입
  - 폴더(연도/카테고리) 무시, 시간순 단일 stream
- **#3 `/records/by-category` — 카테고리 × 연도 매트릭스**:
  - `IndexRepo#category_year_matrix(mode:)` — `GROUP BY category, SUBSTR(created_at, 1, 4)`
  - `views/records/by_category.erb` — 행=카테고리(빈도순) × 열=연도, 셀 클릭 → timeline drill-down
  - 30년 누적 분포 한 화면 + 합계 row/col
- **#5 합성기 "전체 기간 (30년)" preset**:
  - `views/synth/index.erb` — since/until 인풋 있는 5 폼 (reflections / consultations / assessments / lesson-series / +) 에 button (`data-synth-preset="all-time"`)
  - JS: 클릭 시 since=`1990-01-01T00:00`, until=현재 시각 자동 채움
  - 백엔드 합성기는 이미 nil-able since/until 지원 — UI 만 추가
- **CSS**: `.on-this-day*` (위젯) / `.records-timeline*` (필터/연도 divider/item) / `.records-matrix*` (table/cells/totals)
- **`.standard.yml`**: `dist/**/*` ignore 추가 (DMG 빌드 산출물 + `/Applications` symlink 의 다른 .app)
- **spec 신규**:
  - `spec/repositories/index_repo_cross_year_spec.rb` 14 케이스 (on_this_day 5 + flat 6 + matrix 3)
  - `spec/system/records_cross_year_spec.rb` 12 케이스 (timeline 8 + by-category 3 + index 링크 1)
  - `spec/system/dashboard_spec.rb` "이날의 회고" 위젯 3 케이스
- 회귀: 1336 → 1365 (+29). lint clean. 50/50 cross-year spec pass.

### macOS DMG 인스톨러 (2026-05-10) — W8-T03 부분 완료
- **`packaging/macos/build.sh`** 로컬 빌드 스크립트 (macOS only):
  - `Sowing.app` 번들 조립 (Info.plist 버전 치환 + launcher.sh + Resources/sowing/ 소스 복사)
  - rsync 로 spec/log/dist/.git 등 제외 — .app 안에 Ruby 소스만 포함 (~2.5MB)
  - DMG 스테이징: Sowing.app + `/Applications` symlink + `먼저 읽어주세요.txt` 안내
  - `hdiutil create -format UDZO` 압축 → `dist/Sowing-{VERSION}.dmg` (~700KB)
  - SHA256 체크섬 자동 생성 (`*.dmg.sha256`)
  - 환경 변수 `SOWING_CODESIGN_IDENTITY` 있으면 codesign 자동 (`--deep --options runtime --timestamp`)
  - 환경 변수 `SOWING_NOTARIZE_PROFILE` 있으면 notarytool submit + stapler staple 자동
- **`packaging/macos/Info.plist`** — .app 번들 메타데이터:
  - CFBundleIdentifier `com.junkichoLab.sowing`
  - LSMinimumSystemVersion 11.0 (Big Sur+)
  - LSApplicationCategoryType `public.app-category.productivity`
  - 버전은 `__VERSION__` placeholder (build.sh 가 sed 치환)
- **`packaging/macos/launcher.sh`** — `Contents/MacOS/Sowing` 런처:
  - macOS 시스템 Ruby (`/usr/bin/ruby`, 14.4+ 에 3.3.x) 또는 Homebrew Ruby (`/opt/homebrew/opt/ruby/bin`) 자동 탐지
  - Ruby 없거나 3.3 미만 → osascript 다이얼로그 + SETUP.md 자동 open
  - 첫 실행: Terminal 창에서 `bundle install + db:setup + rackup` (1~2분) + 브라우저 자동 open
  - 재실행: Terminal 창에서 dev 서버만 + 브라우저 open
  - `~/Library/Application Support/Sowing/.installed` 마커로 첫 실행 판별
  - 종료: Terminal 창 닫기 또는 ⌃C (lifecycle 명확)
- **DMG 안의 `먼저 읽어주세요.txt`**:
  - 설치 절차 (드래그 → 더블클릭)
  - **Gatekeeper 우회 안내** (우클릭 열기 또는 `xattr -dr com.apple.quarantine`)
  - vault 위치 (`~/Documents/SowingVault`) 안내
  - GitHub repo 링크
- **`.github/workflows/release-macos.yml`** — v 태그 push 시 자동 빌드:
  - `macos-latest` runner 에서 `build.sh` 실행
  - GitHub secrets 등록 시 codesign + notarize 자동 활성화 (env vars 자동 export):
    - `MACOS_CERT_BASE64` / `MACOS_CERT_PASSWORD` → 임시 keychain + p12 import + identity 추출
    - `MACOS_NOTARY_APPLE_ID` / `MACOS_NOTARY_TEAM_ID` / `MACOS_NOTARY_PASSWORD` → notarytool keychain-profile 등록
  - 검증 step: `spctl -a -vvv` (signed 시) + `xcrun stapler validate` (notarized 시)
  - keychain cleanup (`always()` — 인증서 누출 방지)
  - artifact 업로드 (`*.dmg` + `*.dmg.sha256`, 90일)
  - GitHub Release 에 자동 첨부 (기존 release.yml 산출물에 추가)
- **`packaging/macos/README.md`** 신규 — 빠른 빌드 / 사용자 UX / Apple Dev 계정 확보 시 정식 절차 / 아이콘 ICNS 생성 / TODO 체크리스트
- **`packaging/README.md` 매트릭스 갱신** — macOS DMG (unsigned) ✅ 완료, signed/notarized 🟡 인프라 완료
- **`README.md` 시작하기** — "macOS DMG 다운로드" 항목 추가
- 로컬 검증 (macOS 14.4 + arm64):
  - `./packaging/macos/build.sh` → `Sowing-0.1.0.dmg` 생성 (709KB)
  - `hdiutil verify` OK
  - DMG 마운트 → 3 항목 확인 (`Sowing.app`, `Applications` 심볼릭, `먼저 읽어주세요.txt`)

(다음 릴리스 변경사항 누적용 — 비어 있으면 최근 릴리스가 모두 반영됨.)

## [0.1.0] - 2026-05-10 — 첫 정식 release (MVP + Phase 9~12 + 확장 + 베타 인프라 + 4 설치 경로)

**Sowing 의 첫 GitHub Release.** Phase 1 (W1~W8 MVP) 부터 Phase 12 (W21~W24
Tier-2 LLM 합성), 8 확장 합성기, 베타 검증 인프라, 4 즉시 설치 경로까지 모두
포함. 1332 spec pass, lint clean, eval 회귀 0.

**규모**: 14 컨트롤러 / 91 라우트 / 12 LLM 합성기 (`/synth` 12 type) + 12 MCP
도구 + 100 eval corpus + 12 평가 차원 + Phase 11~12 audit preference 데이터
누적 인프라. 4 설치 경로 (Docker / sowing-install / 소스 / Homebrew Tap).

### 패키징·배포 인프라 — 4 즉시 가능한 설치 경로 (2026-05-10)
- KICKOFF P2.4 옵션 B (W8 deferred 패키징) 의 *외부 리소스 없이 즉시 가능한* 5 deliverable. Apple Developer 계정·Windows VM·Tebako runtime 필요한 정식 인스톨러는 그대로 deferred.
- **Dockerfile** + **`docker-compose.yml`** + **`.dockerignore`**:
  - Multi-stage build (builder/runtime), ruby:3.3-slim 베이스
  - 한국어 locale (C.UTF-8) + Asia/Seoul timezone
  - 기본 포트 48723, 헬스체크 30초 간격 (`/health` 폴링)
  - 첫 부팅 시 `db:setup` 자동 실행
  - vault 호스트 마운트 (`./vault → /vault`), data named volume (`sowing-data → /data`)
  - rackup `0.0.0.0` 바인딩 (bin/sowing dev 가 127.0.0.1 hardcode 라 컨테이너용 분리)
  - 5초 셋업 — `docker compose up -d`
- **`bin/sowing-install`** (curl-installable bootstrap):
  - macOS / Linux 자동 OS 탐지 (Windows 는 WSL2/Docker 안내)
  - Ruby 3.3+ 검증, Bundler 자동 설치
  - 저장소 clone (`~/.sowing/app`) 또는 업데이트 (기존 발견 시)
  - bundle install (production only) + db:setup
  - sowing-doctor 진단 + 첫 실행 안내 (alias 등록 가이드)
  - 사용: `curl -fsSL https://raw.githubusercontent.com/junkicho-lab/sowing/main/bin/sowing-install | bash`
- **`packaging/homebrew/sowing.rb`** — Homebrew Tap formula (Apple Developer 계정 불필요):
  - `brew tap junkicho-lab/sowing && brew install sowing`
  - `depends_on "ruby" ~> 3.3` + `sqlite` + `libyaml`
  - `bin/sowing` / `bin/sowing-doctor` / `bin/sowing-mcp` shim 자동 등록
  - 첫 실행 안내 + 기본 vault 위치 표시
  - `.standard.yml` exclude 추가 (Homebrew DSL 의 Pathname `/` 연산자 관례)
- **`.github/workflows/build.yml`** — Cross-platform CI 빌드 매트릭스:
  - macOS / Ubuntu / Windows runner 3종에서 매 push/PR 시
  - Ruby 3.3 setup → bundle → spec → lint → doctor → source ZIP artifact (14일)
  - Docker 이미지 빌드 + 컨테이너 healthcheck (`/health` 30초 폴링)
  - Windows 는 lint/doctor 일부 건너뜀 (인코딩 호환 검증 추후)
- **`bin/sowing-doctor` 환경 섹션 확장**: 설치 모드 자동 탐지
  - `/.dockerenv` 존재 → "docker"
  - `~/.sowing/app/` 안 → "sowing-install"
  - `Cellar/` 또는 `HOMEBREW_PREFIX` → "homebrew"
  - `.git/` 존재 → "source (git clone)"
  - 그 외 → "unknown"
- **`packaging/README.md` 전면 갱신** — 현재 상태 매트릭스:
  - ✅ 완료: Docker / sowing-install / 소스 / GitHub Actions CI
  - 🟡 부분: Homebrew Tap (formula 작성, Tap 저장소 별도) / Tebako 스캐폴드
  - ⏳ Deferred: macOS DMG / Windows Inno Setup / Linux AppImage / 시스템 트레이 (외부 리소스 필요)
- **`README.md` 시작하기 섹션 전면 갱신**:
  - "현재는 소스 빌드만" → 4 가지 설치 경로 (Docker / sowing-install / 소스 / Homebrew Tap)
  - 각 경로의 명령 + vault 위치 안내
- 검증:
  - 1332 spec pass (코드 변경 없음 — 인프라만 추가)
  - lint clean
  - 시 sowing-doctor: 새 "설치 모드: source (git clone)" 라인 정상 출력
  - GitHub Actions 트리거는 다음 push/PR 시 자동 검증

### 베타 사용자 검증 인프라 (2026-05-10)
- **`Sowing::UseCases::ComputeSynthMetrics`** 신규 — `vault/.sowing/audit.log` JSON Lines 분석 → 합성기 사용 지표 집계
  - synth_generate / synth_accept / synth_reject 이벤트만 필터
  - **path 필드에서 type 추출** (`.sowing/synth/{type}/{slug}.md`) — accept entry_id 가 새 Record ULID 라 path 만 신뢰
  - 출력:
    - **totals**: generate / accept / reject / pending / **acceptance_rate** (Phase 11 마일스톤 ≥ 50%)
    - **by_type**: 12 type 별 카운트·수락률
    - **by_week**: ISO 주별 집계 (시간순)
    - first_event_at / last_event_at / duration_days / event_count
  - 가드: 음수 pending 방지 (`[gen - decided, 0].max`) — 재생성 시 generate 가 누적되어도 안전
  - read-only — vault·DB 변경 없음
  - since/until 필터로 베타 기간 한정 가능
  - spec 9건 (Failure / 다른 action 무시 / totals / by_type / by_week / since-until / 엣지 2)
- **`rake stats:synth_metrics`** — CLI 리포트 (텍스트, 막대 그래프 포함)
  - `SOWING_SINCE` / `SOWING_UNTIL` 환경 변수로 기간 지정
  - 전체 + type 별 + 주별 (최근 8주) 표시
- **`rake stats:beta_report`** — 마크다운 리포트 (stdout)
  - 인터뷰 자료·운영 보고용
  - Phase 11 마일스톤 ✅/🟡 자동 평가
- **`/synth/metrics`** — 실시간 대시보드 (브라우저)
  - 전체 지표 + Phase 11 마일스톤 마커 + type 별 표 + 주별 추이 + CLI 리포트 안내
  - `synth-metrics__rate--ok` 50% 이상 색상 강조
  - 라우트 우선순위 — `/synth` 다음, `/synth/:type/:slug` 이전
- **views/synth/index.erb**: "📊 사용 지표 보기" 링크 추가
- **CSS**: `.synth-metrics__rate` (수락률) / `.synth-metrics__milestone` / `.synth-metrics__table` / `.synth-metrics__bar` 스타일
- **베타 운영 문서 2종**:
  - `docs/BETA_GUIDE.md` — 베타 테스터용 가이드 (부탁사항 / 마일스톤 기준 / 측정 도구 / ADR-013 약속 / 사적 데이터 보호 / 인터뷰 6 질문)
  - `docs/BETA_RECRUITMENT.md` — 운영자용 모집 절차 (대상 / 채널 / 모집 글 템플릿 / 선정 후 절차 / 데이터 수집 동의 / ROADMAP 마일스톤 갱신)
- 대시보드 spec 3건 (이벤트 0건 빈 상태 / 50% 이상 마일스톤 ✅ / 50% 미만 🟡)
- 회귀: 1320 → 1332 (+12 = use case 9 + dashboard 3). lint clean. eval 회귀 0. 5× stress 안정 (67/67 × 5).

**다음 단계**: 베타 테스터 5명 모집 → 한 학기 사용 → audit.log 분석 + 인터뷰 → ROADMAP Phase 11/12 마일스톤 블록 갱신. 인프라는 모두 준비됨.

### 확장 합성기 #6 — 수업 시리즈 추적 (2026-05-10)
- **`Sowing::UseCases::SynthesizeLessonSeries`** 신규 — 단원·주제 키워드 기반 차시별 timeline
  - 한 단원이 5~10차시에 걸쳐 흩어진 entries 를 한 화면에 수집
  - 입력: keyword (예: "분수") + 6개월 default window. title 또는 body 매칭
  - 결정적 출력: 차시별 timeline + mode 아이콘 + 모드 분포 + **단원 종료 자동 감지** (마지막 entry 후 14일 경과 시 ✅ 종료, 미만이면 🟢 진행 중)
  - LLM 출력 4 섹션 (🎒 단원 흐름 / 👥 학생 반응 변화 / 🌱 잘된/아쉬웠던 차시 / 📚 다음 단원 준비)
  - 저장: `vault/.sowing/synth/lesson-series/{keyword}.md`
  - frontmatter 12키 (synth_keyword + synth_status + synth_first/last_date + synth_duration_days)
  - 가드: MIN_ENTRIES=2 / MAX_ENTRIES=200 / ENDED_AFTER_DAYS=14
  - 자율 판단 0: "이 단원이 잘됐다" 단정 X — 차시별 인용 + 시간 흐름만
  - accept_category=수업기록, target_prefix=series:
- spec 11건

### 확장 합성기 #7 — 태그 클러스터 (2026-05-10)
- **`Sowing::UseCases::SynthesizeTagClusters`** 신규 — 자주 함께 등장하는 태그들 → 주제 그룹 발견
  - "내가 무엇에 대해 자주 쓰는가" 자기 인식 도구
  - 알고리즘 (결정적):
    - 빈도 ≥ 2 인 태그만 후보 (1번 쓰인 태그는 클러스터링 가치 없음)
    - 모든 태그 페어 co-occurrence 카운트 + Jaccard 유사도 (`|A∩B|/|A∪B|`)
    - JACCARD_THRESHOLD=0.3 + MIN_PAIR_COUNT=2 필터
    - **union-find 클러스터링** — 페어 임계 넘으면 같은 그룹으로 merge
    - 클러스터당 대표 entries (그룹 태그를 가장 많이 가진 top 3)
  - 결정적: 태그 그룹 + 고유 entries 카운트 + 대표 entries wikilink
  - LLM: 그룹별 라벨 제안 + 자기 발견 질문 + 메타-관찰
  - 저장: `vault/.sowing/synth/tag-clusters/topics.md` (단일 파일)
  - frontmatter 9키 (synth_jaccard_threshold + clustered_tags + total_unique_entries)
  - 같은 태그가 여러 클러스터에 들어가지 않음 (단순 union)
  - accept_category=주제정리, target_prefix=clusters:
- spec 9건

### 확장 합성기 #8 — 계절성 패턴 (2026-05-10)
- **`Sowing::UseCases::SynthesizeSeasonalPattern`** 신규 — 같은 월의 여러 연도 entries 비교
  - "매년 이 시기에 비슷한 어려움이 반복된다" 발견. **연차 1년 후부터 폭발적 가치** — 지금 인프라만 깔아두면 나중에 자동으로 의미 누적 (long-term play)
  - 입력: month (1~12, default = 이번 달). SQLite SUBSTR(created_at, 6, 2) 로 월 추출
  - 연도별 그룹 + 작년/재작년/올해 timeline 비교 + 모드·카테고리 분포
  - 결정적: 연도별 timeline + **올해 마커** 🎯 + 모드 분포
  - LLM (분기): 2년치 이상 → "매년 반복 / 매년 다른 / 올해 시도해볼 만한"; 1년 미만 → "이번 달 흐름 / 핵심 사건 / 다음 달 준비"
  - 저장: `vault/.sowing/synth/seasonal/{MM}.md` (월당 1 파일, 매년 갱신)
  - frontmatter 11키 (synth_month + synth_years + synth_year_counts + synth_pattern_eligible)
  - 가드: MIN_ENTRIES=3 / MAX_ENTRIES=1000 / MIN_YEARS_FOR_PATTERN=2
  - 1년 미만 사용 시 안내: "씨를 뿌리는 단계"
  - 자율 판단 0: "이 시기에 항상 ~한다" 단정 X — *반복으로 보이는 후보* 만
  - accept_category=계절회고, target_prefix=season:
- spec 13건

### 확장 합성기 #6 + #7 + #8 통합 검증
- `SynthController::SYNTH_TYPES` 12 type 으로 확장 (lesson-series + tag-clusters + seasonal)
- 새 generate routes 3종:
  - `POST /synth/lesson-series/:slug/generate` (slug=키워드)
  - `POST /synth/tag-clusters/topics/generate` (매개변수 0)
  - `POST /synth/seasonal/:slug/generate` (slug=MM 또는 "current")
- views: 3 섹션 + 폼 + 재생성 버튼 + JS slug fallback (`encodeURIComponent`)
- bin/sowing-doctor: 5 use case → 8 (확장 #1~#8) + 12 디렉토리 카운트
- 대시보드 spec 11건 신규 (lesson-series 4 + tag-clusters 3 + seasonal 4)
- 회귀: 1276 → 1320 (+44 = lesson-series 11 + tag-clusters 9 + seasonal 13 + dashboard 11). lint clean. `rake eval:run` 회귀 0. 5× stress 안정 (88/88 × 5).
- **합성기 12종, SYNTH_TYPES 12 type 완성** — 학생/학기/패턴/변화/상담/평가/연수/주간/고립/시리즈/클러스터/계절성

### 확장 합성기 #4 — 주간 회고 (2026-05-10)
- **`Sowing::UseCases::SynthesizeWeeklyReview`** 신규 — 한 주 단위 자동 회고
  - 학기 회고(W21-T01)와 학생 디제스트(W17-T02) 사이의 빠진 호흡. 매주 일요일 트리거 가능.
  - 입력: 최근 7일 entries (default = 자동 ISO 주, 월요일 ~ 일요일)
  - `week_label` / `since` / `until_time` 모두 nil 이면 `clock.now` 기준 자동 ISO 주 (예: "2026-W19")
  - 결정적 출력 4 섹션:
    - 📅 이번 주 요약 (모드별 카운트 + 카테고리)
    - 📊 일별 작성 빈도 (한국 요일 라벨 — 월/화/수… + 막대 `▌`)
    - 👥 자주 등장한 학생 (top 5 — entity_mentions ⨝ entities)
    - ☐ 미완료 task (본문 `- [ ]` / `* [ ]` 패턴 추출, `- [x]` 완료 제외)
  - LLM 출력 4 섹션 (🌊 흐름 / 💡 작은 발견 / ☐ 미해결 / 🎯 다음 주 우선순위)
  - 저장: `vault/.sowing/synth/weekly/{YYYY-WW}.md` (ISO 주 라벨)
  - frontmatter 8키: 기본 + `synth_period_*` + `synth_incomplete_task_count`
  - 가드: MIN_ENTRIES=1 (적게 쓴 주의 알림 가치도 인정) / MAX_ENTRIES=200
  - task 20개 초과 시 첫 20개만 + "그 외 N건" 안내
  - 자율 판단 0: "잘했다/못했다" 단정 X — 통계 + 인용 + task 만 객관적으로
  - audit `with_actor("agent")` + LLM 실패 fallback
- **`SynthController::SYNTH_TYPES`** 8 type 으로 확장 — weekly 추가 (label="주간 회고", icon=📆, accept_category=주간회고, target_prefix=week:)
  - 새 generate route: POST /synth/weekly/generate (week_label/since/until 모두 옵션)
- spec 17건 (결정적 5 + 인자 명시 2 + 가드 2 + task 패턴 1 + LLM 3 + 엣지 4)

### 확장 합성기 #5 — 고립 메모 발견 (2026-05-10)
- **`Sowing::UseCases::DetectOrphanEntries`** 신규 — backlink 0건 entries 식별
  - W3 위키링크 그래프 인프라 위에 얹는 발견 도구. "쓴 적 있는데 어떤 다른 글에서도 인용 안 했다 = 잠재적 통찰 / 미발견 패턴".
  - 입력: 1년 lookback (default) + IndexRepo.links_to(id) = 0건인 entries
  - `exclude_modes` 인자로 mode 별 제외 가능 (예: memo 제외 → 정식 글만)
  - 결정적 출력:
    - 🌊 고립 entries 목록 (시간순 + mode 아이콘 + outbound 링크 수 표시)
    - 모드별·카테고리별·태그별 분포 (클러스터 발견 단서)
    - 본문 첫 문장 발췌 + wikilink 출처
  - LLM 출력 3 섹션 (🌊 고립 패턴 / 🔗 연결 후보 제안 / 💭 본질적 고립 인정)
  - 저장: `vault/.sowing/synth/orphans/observations.md` (단일 파일, 누적 갱신)
  - frontmatter 9키: 기본 + `synth_period_*` + `synth_excluded_modes` + `synth_orphan_tags`
  - 가드: MIN_ORPHANS=1 / MAX_ORPHANS=100 (한 화면 의미)
  - 자율 판단 0: "이 글이 고립이다" 만 표시. 연결은 사용자 판단. trailer "본질적으로 고립일 수도 있어요"
  - **broken link (target_id NULL) 처리** — 깨진 위키링크는 backlink 으로 카운트 안 됨 (자기 자신은 여전히 고립)
  - audit `with_actor("agent")` + LLM 실패 fallback
- **`SynthController::SYNTH_TYPES`** 9 type 으로 확장 — orphans 추가 (label="고립 entries 관찰", icon=🌊, accept_category=메모회고, target_prefix=orphans:)
  - 새 generate route: POST /synth/orphans/observations/generate (매개변수 0)
- spec 15건 (결정적 5 + 가드 4 + LLM 3 + 엣지 3)

### 확장 합성기 #4 + #5 통합 검증
- views/synth/{index,show}.erb: weekly + orphans 섹션·폼·재생성 버튼 추가
- bin/sowing-doctor: Phase 12 진단 섹션에 use case 5종(확장 #1~#5) + 9 디렉토리 카운트
- 대시보드 spec 8건 신규 (weekly 4 + orphans 4)
- 기존 7 type spec 백워드 호환 무수정 통과 (32+5+10 = 47건)
- 회귀: 1236 → 1276 (+40 = weekly 17 + orphans 15 + dashboard 8). lint clean. `rake eval:run` 회귀 0. 5× stress 안정 (76/76 × 5).

### 확장 합성기 #2 — 평가 누적 (2026-05-10)
- **`Sowing::UseCases::SynthesizeAssessmentTrend`** 신규 — 학생 1명의 단원평가 누적 추이
  - 입력: 학생 entity + 6개월 window + 평가 카테고리 (default 평가/단원평가)
  - 학생 이름 + 평가 키워드 (단원/평가/시험/수행/형성평가/단원평가/수행평가) 둘 다 본문 만족 entry 만 포함
  - 단원 라벨 자동 추출 — 평가 키워드 직전 1~2 어절 = 단원명 ("분수 단원" / "도형 단원평가" / "곱셈 수행평가")
  - 강점/약점 분류 (Phase 12 LessonPattern 패턴 재사용) — STRENGTH 13종 + WEAKNESS 12종 키워드 + 부정 윈도 5자 필터 ("잘 못 풀었다" 무효)
  - 두 모드:
    - **결정적**: 시간순 단원별 인용 + 강점/약점 후보 분류 + 출처 wikilink
    - **LLM 옵트인**: 4 섹션 (📊 단원별 추이 / 💪 강점 / 🌱 보강 필요 / 📚 다음 학습 우선순위)
  - 저장: `vault/.sowing/synth/assessments/{학생명}.md`
  - frontmatter 11키: 기본 + `synth_period_*` + `synth_categories` + `synth_units` (분석된 단원 배열) + `synth_strength_count` / `synth_weakness_count`
  - 가드: MIN_ENTRIES=2 / MAX_ENTRIES=200 / 6개월 default window
  - 자율 판단 0: 학생 능력 단정 X — 인용 + 단원명 + 날짜만, 점수·등급은 LLM 가공 안 함
  - audit `with_actor("agent")` + LLM 실패 fallback
- **`SynthController::SYNTH_TYPES`** 6 type 으로 확장 — assessments 추가 (label="평가 추이", icon=📊, accept_category=평가기록, target_prefix=assessment:)
  - 새 generate route: POST /synth/assessments/:slug/generate (slug=학생 이름, since/until 옵션)
- spec 22건 (use case 18 + 대시보드 4)
- 회귀: 1188 → 1206 (+18). lint clean. eval 회귀 0.

### 확장 합성기 #3 — 연수 흡수 (2026-05-10)
- **`Sowing::UseCases::ExtractTrainingApplications`** 신규 — 연수 노트 ↔ 실제 수업 적용 사례 매칭
  - 입력: 연수 노트 1건 (notes 의 `category="trainings"`, slug=entry id) + 그 후 default 90일 안의 entries
  - 매칭 알고리즘 (결정적):
    - 연수 본문에서 한국어 어절 분리 → 조사 제거 (`KOREAN_PARTICLES` 18종) → 불용어 (`STOPWORDS` 35종 — 오늘/학생/우리 등) 제거 → 빈도 상위 12개 키워드
    - 후속 entries 의 각 문장이 키워드 1개 이상 포함하면 적용 후보 + D+N 일 차 (달력 일수 기반)
    - entry path 기준 dedupe — 한 entry 가 여러 키워드 매칭돼도 1회만
  - 두 모드:
    - **결정적**: 키워드 목록 + D+N 시점별 적용 후보 + wikilink 인용
    - **LLM 옵트인**: 4 섹션 (📚 연수 핵심 요약 / ✨ 적용된 사례 / 🌱 미적용 영역 / 💡 다음 적용 후보)
  - 저장: `vault/.sowing/synth/trainings/{training_id}.md` (연수 1건당 1 파일)
  - frontmatter 11키: 기본 + `synth_training_path` / `synth_training_date` / `synth_followup_days` / `synth_keywords` / `synth_unmatched_keywords`
  - 본문 상단에 원본 연수 wikilink 명시 — 사용자가 출처 즉시 확인 가능
  - 가드: MIN_KEYWORD_LENGTH=2 / MAX_KEYWORDS=12 / MAX_FOLLOWUP_ENTRIES=200
  - 자율 판단 0: 결정적 매칭은 *키워드 일치* 일 뿐 — 진짜 적용은 사용자 판단. trailer "각 매칭은 *후보* 일 뿐 — 실제 적용 여부는 교사 본인이 판단"
  - audit `with_actor("agent")` + LLM 실패 fallback
- **`SynthController::SYNTH_TYPES`** 7 type 으로 확장 — trainings 추가 (label="연수 적용 추적", icon=🎓, accept_category=연수기록, target_prefix=training:)
  - 새 generate route: POST /synth/trainings/:slug/generate (slug=연수 entry id, followup_days 옵션 폼)
- **ROADMAP 검증 시나리오 3종 모두 spec 통과**:
  1. 연수 후 즉시 적용 (D+1)
  2. 한 달 후 적용 (D+30)
  3. 미적용 (후속 entries 0 + 안내 문구)
- spec 27건 (use case 21 + 대시보드 5 + 시나리오 3종 use case 안 포함)
  - 결정적 6 + 시나리오 3 + 가드 5 + LLM 3 + 엣지 4
- 회귀: 1206 → 1236 (+30 = use case 21 + 대시보드 5 + 추가 시나리오 4). lint clean. eval 회귀 0.

### 확장 합성기 #1 — 학부모 상담 준비 (2026-05-10)
- **`Sowing::UseCases::SynthesizeParentConsultation`** 신규 — 학생 1명에 대한 학부모 면담 준비 자료 자동 합성
  - KICKOFF P2.4 옵션 C (확장 합성기 추가) 의 첫 구현. Phase 11~12 합성기 패턴 그대로 확장.
  - 입력 3 갈래 통합:
    1. records 의 `category ∈ DEFAULT_CONSULTATION_CATEGORIES` (default: 상담/학부모상담)
    2. notes 의 `category ∈ DEFAULT_CONSULTATION_NOTE_CATEGORIES` (default: meetings)
    3. 학생 entity mention entries 중 본문에 `DEFAULT_CONSULTATION_KEYWORDS` 포함 (default: 학부모/면담/상담/부모님/가정)
  - 3 갈래 통합 후 entry id 기준 UNIQUE → 학생 이름 또는 상담 키워드 본문 필터 → 시간순 정렬
  - 두 모드:
    - **결정적**: 시간순 인용 모음 + mode 아이콘 (💭/📝/📖) + 카테고리 라벨 + 출처 wikilink. trailer "원자료 — 교사의 직접 판단·맥락이 우선"
    - **LLM 옵트인**: 4 섹션 출력 (🌱 학생 강점 / 🔄 변화·성장 / 💬 학부모와 공유할 만한 관찰 / 🤝 가정에서 함께 시도해 볼 만한 것). prompt: "단정·낙인·사적 평가 금지", "본문에 없는 사실 만들기 금지", 가정 제안은 "~을 함께 해보면 어떨까요" 톤
  - 저장: `vault/.sowing/synth/consultations/{학생명}.md`
  - frontmatter 9키: 기본 6키 + `synth_period_since` / `synth_period_until` / `synth_categories`
  - 가드: `MIN_ENTRIES=2` / `MAX_ENTRIES=200` / `EXCERPT_LIMIT=200` / 6개월 default window
  - LLM 실패 → 결정적 fallback (Phase 11~12 패턴 동일)
  - audit `with_actor("agent")` Thread-local 스택 통합
  - **자율 판단 0** (ADR-013): "이 학생은 ~한 학생입니다" 단정 X — 인용 + 출처 + 날짜만. 학부모와 공유 가능한 *관찰* 만 (사적 추측·심리 분석 금지)
- **`SynthController::SYNTH_TYPES`** 5 type 으로 확장
  - `consultations` 추가 (subdir/label="학부모 상담 준비"/icon=🤝/accept_category=상담/target_prefix="consultation:")
  - 새 generate route: `POST /synth/consultations/:slug/generate` (slug=학생 이름, since/until 옵션 폼)
  - accept 시 → `30_Records/{YYYY}/상담/` 으로 저장
  - 기존 4 type 백워드 호환 — 모든 기존 spec 무수정 통과
- **views**:
  - index.erb: 학부모 상담 generate 폼 (학생 이름 + since/until) + JS fallback (학생 이름 → action URL escape)
  - show.erb: consultations type 재생성 버튼
- **bin/sowing-doctor**: Phase 12 진단 섹션에 SynthesizeParentConsultation use case + consultations 디렉토리 카운트 추가
- spec 22건 (use case 17 + 대시보드 5 신규)
  - 결정적 5: Success/frontmatter 9키/본문 wikilink/시간순 정렬/trailer 톤
  - 입력 필터링 2: 학생 이름·키워드 필터 / 사용자 정의 categories
  - 가드 4: entity_not_found / no_entries / too_many_entries / default 6개월 window
  - LLM 3: 1회 호출 / agent actor / 실패 fallback
  - 엣지 3: 멱등 / vault 누락 graceful / 중복 입력 1회만
  - 대시보드 통합 5: generate route / 학생 없음 fail / accept→상담 카테고리 / reject audit / 5 섹션 표시
- 회귀: 1166 → 1188 (+22). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.

### Phase 12 (Tier-2 LLM 합성) 완료 (W21-T01 ~ T04, 2026-05-10)
- **W21-T04 완료** (2026-05-10): 통합 `/synth` 대시보드 — 4 type (디제스트·회고·패턴·변화) 한 화면
  - `Sowing::Controllers::SynthController` 전면 리팩토링 — `SYNTH_TYPES` 상수로 4 type 메타데이터 통합 관리
    - 각 type: `subdir` / `label` / `icon` / `accept_category` / `target_prefix`
  - 통합 라우트:
    - `GET /synth` — 4 섹션 통합 대시보드 (각 섹션 `<details>` 접고 펼침, items 있으면 자동 open)
    - `GET /synth/:type/:slug` — 통합 상세 (메타 dl 8키 — synth_period_since/until, synth_categories, synth_students 등 type별 메타도 자동 표시)
    - `POST /synth/:type/:slug/accept` — type별 accept_category 매핑 (학생기록/학기회고/수업기록/학생기록) → Record + `Persistence#persist!`
    - `POST /synth/:type/:slug/reject` — `.sowing/trash` 휴지통 mv + audit (entry_id prefix=type별 target_prefix)
    - `POST /synth/students/:slug/generate` (기존 — 학생 이름)
    - `POST /synth/reflections/generate` — `semester_label` 필수 + `since`/`until` 옵션 폼
    - `POST /synth/patterns/lessons/generate` — 매개변수 0 (고정 slug)
    - `POST /synth/contradictions/observations/generate` — 매개변수 0 (고정 slug)
  - **"이번 주 새로 합성됨" 배지** (`recently_synthed?` 헬퍼, `RECENT_DAYS=7`) — 7일 이내 synth_at 시 노란색 펄스 애니메이션 배지
  - 카테고리 매핑 (수락 시):
    - students → 30_Records/{YYYY}/학생기록/
    - reflections → 30_Records/{YYYY}/학기회고/
    - patterns → 30_Records/{YYYY}/수업기록/
    - contradictions → 30_Records/{YYYY}/학생기록/
  - 백워드 호환: 기존 `/synth/students/:slug/{accept,reject,generate}` 라우트 유지 — 새 `:type/:slug` 패턴이 자동 매칭
  - views/synth/{index,show}.erb 전면 갱신 + 4 섹션 collapsible UI + 4 type별 생성 폼 + type 배지
  - CSS: `.synth-section` (collapsible) + `.synth-badge--type` + `.synth-badge--recent` (펄스 애니메이션) + `.synth-generate-form`
  - bin/sowing-doctor: 16번째 진단 섹션 "[Tier-2 LLM 합성 (Phase 12)]" 신규 — 3 use case + SynthController::SYNTH_TYPES 4 type + 4 디렉토리 카운트
  - spec 22건 (대시보드 4 + 상세 5 + 수락 4 + 거절 2 + 생성 5 + ADR-013 자율 mutation 0 검증 1 + 배지 1)
    - 모든 합성 산출물 4 type 한 페이지 접근 검증
    - "이번 주 새로 합성" 배지 카드별 정확 등장 — `body.scan` 으로 카드 영역 분리 검증
    - reject audit entry_id prefix 4 type 모두 검증 (semester:/student:/patterns:/contradictions:)
    - 알 수 없는 type → 404, 알려진 type slug 누락 → 404
    - reflections 폼 — semester_label 빈 입력 시 합성 시도 안 함 (audit 변동 0)
  - 회귀: 1144 → 1166 (+22). lint clean. `rake eval:run` 회귀 0. 5× stress 안정 (32/32 × 5).
- **W21-T03 완료** (2026-05-10): ContradictionDetector — 학생 묘사 시간순 변화 후보
  - `Sowing::UseCases::DetectContradictions` — 학생 mention 시간순 분석 → 반의어 차원 양 끝 매칭 → 변화 후보 + 방향(향상/후퇴)
  - 4 차원 (`ANTONYM_DIMENSIONS`):
    - **참여도**: low(소극/조용/발표 안/시선 안/듣는 역할) ↔ high(적극/자원/주도/활발/능동)
    - **집중도**: low(산만/딴짓/멍하/집중력 부족) ↔ high(집중/몰입/차분/진지)
    - **이해도**: low(어려워/못 따라/부진/헤매/헷갈) ↔ high(잘 이해/또래 이상/빠르게 풀)
    - **협력성**: low(혼자/외톨이/갈등/다툼) ↔ high(협력/모둠 잘/친구들과 잘/사회자 역할)
  - 두 모드:
    - **결정적**: 학생당 시간순 entry → 본문 문장 분리 → 학생 이름 포함 문장만 분석 → 차원별 low/high 매칭 → 양 끝 모두 등장 시 변화 후보 (향상/후퇴 방향 자동 판정 — 시간 순서 기반)
    - **LLM 옵트인**: 1차 후보 → 종합 prompt → 변화 시점 + 가능한 분기점 사건 + 다음 관찰 제안
  - 톤 (ADR-013 자율 판단 0):
    - "모순" 대신 *변화·발견* (con-001 corpus notes 와 일치 — "비판이 아니라 통찰로")
    - 결정적 trailer "각 변화는 후보일 뿐 — 사용자가 검토 후 *발견* 으로 받아들일 것"
    - LLM prompt 도 "단정 금지 — 분기점은 본문에 명시된 사건만"
    - 인용 근거(entry path + 문장 + 날짜) 항상 양 끝 함께 제시
  - 저장: `vault/.sowing/synth/contradictions/observations.md` (단일 파일, 학생 전체 누적)
  - frontmatter 9키: 기본 6키 + `synth_period_since` / `synth_period_until` / `synth_students` (분석된 학생 이름 배열)
  - 가드: `MIN_OBSERVATIONS=1` (1명만 변화 보여도 의미 — gap 알림과 비슷, 적극적 톤) / `MIN_MENTIONS_PER_STUDENT=2` (변화 추적 가능 최소) / `EXCERPT_LIMIT=200`
  - 결정적 모드 한계 인정: 반의어 사전 외 어휘 미탐지 (예: "내성적/외향적"). false positive 가능성 — 같은 차원 다른 맥락 사용 시 변화로 오인 → 사용자 검토 의무화
  - LLM 실패 → 결정적 fallback (Phase 11~12 합성기 패턴 동일)
  - audit `with_actor("agent")` 통합
  - **의도적 모순 시나리오 5종 spec 검증** (ROADMAP 검증 기준 충족):
    1. 참여도 향상 (발표 안 → 자원)
    2. 집중도 향상 (산만 → 집중)
    3. 이해도 향상 (어려워 → 또래 이상)
    4. 협력성 향상 (혼자 → 모둠 잘)
    5. 후퇴 방향 (적극 → 소극, 화살표 → 후퇴 표시)
  - spec 18건 (의도 시나리오 5 + 산출물 형식 3 + 가드·엣지 7 + LLM 3)
  - 회귀: 1126 → 1144 (+18). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.
- **W21-T02 완료** (2026-05-10): LessonPattern 추출 — 잘된/아쉬웠던 수업 후보 인용
  - `Sowing::UseCases::ExtractLessonPatterns` — 수업 카테고리 entries → 긍정/부정 신호어 매칭 → 패턴 후보 인용 모음
  - 두 모드:
    - **결정적**: 문장 단위 키워드 매칭 (POSITIVE 19종: 잘됐/성공/활기/집중/흥미/참여/효과적/만족/보람/자발/적극/협력/몰입/감동 등 / NEGATIVE 17종: 어려웠/힘들/산만/부족/아쉬웠/실패/혼란/지루/소극적/시간 부족/효과 적었/처졌 등). **부정 표현 5자 윈도 필터** — `안`/`못`/`없`/`지 못`/`하지 못` 직후·앞 5자 안에 키워드 있으면 매칭 무효화 ("잘 안 됐다" → "잘" 무효)
    - **LLM 옵트인**: 1차 필터된 인용 → 단일 종합 prompt (청크 분할 없음, 인용 수가 제한적이라 단일로 충분) → 패턴 후보 + "다음 수업에 시도할 만한 것" 섹션
  - 저장: `vault/.sowing/synth/patterns/lessons.md` (학생 디제스트가 학생당 1 파일인 것과 대비, 패턴은 단일 파일에 누적 재합성)
  - frontmatter 9키: 기존 6키 + `synth_period_since` / `synth_period_until` / `synth_categories` (분석 대상 카테고리 목록)
  - 기본 카테고리 (`DEFAULT_LESSON_CATEGORIES`): `수업` / `수업회고` / `lessons` / `도덕` / `도덕수업` — `categories:` 인자로 override
  - 가드: `MIN_ENTRIES=3` / `MAX_ENTRIES=500` / `EXCERPT_LIMIT=200` / `TOP_PATTERN_N=8`
  - 정직성 (ADR-013): "패턴이다" 단정 안 함, 후보 인용만 모음. 결정적 모드 trailer 명시 — "각 인용은 후보일 뿐 — 사용자가 검토 후 *발견* 으로 받아들일 것" (LLM 단정 거부, 자율 판단 0)
  - LLM 실패 → 결정적 fallback (Phase 11 패턴)
  - audit `with_actor("agent")` — Thread-local 스택 (Phase 11~12 합성기 패턴)
  - spec 17건 (결정적 5: 작성/frontmatter/긍정 매칭/부정 매칭/trailer + 카테고리/가드 4: 기본 카테고리/사용자 정의/no_entries/too_many_entries + LLM 4: 1회 호출/synth_model/agent actor/실패 fallback + 엣지 3: 빈 후보/멱등/vault 파일 누락 graceful) + 부정 윈도 검증 1
  - 회귀: 1109 → 1126 (+17). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.
- **W21-T01 완료** (2026-05-10): SemesterReflection 합성기 — 학기 회고 자동 합성 (청크 분할)
  - `Sowing::UseCases::SynthesizeSemesterReflection` — 입력: 학기 분량 entries (default 6개월)
  - 두 모드:
    - **결정적**: 모드별 카운트 + top-N 학생/카테고리 + 월별 청크 타임라인 (위키링크 인용 보존). LLM 미사용 1급.
    - **LLM 옵트인**: 월 단위 청크 → 청크별 요약 → 종합 prompt (long-context 한계 우회 — backend 의 작은 context window 도 안전). 5 섹션 출력 (이번 학기 흐름 / 변화의 순간들 / 잘된 점 / 아쉬웠던 점 / 다음 학기 준비)
  - 저장: `vault/.sowing/synth/reflections/{semester_label}.md` (`.sowing/` prefix watcher 회피)
  - frontmatter 8키: `is_synth` / `synth_target: "semester:{label}"` / `synth_at` / `synth_source_count` / `synth_period_since` / `synth_period_until` / `synth_model` / `title`
  - 입력 가드: `MIN_ENTRIES=5` (회고 가치) / `MAX_ENTRIES=1000` (안전, token 폭발 방지) → `Failure(:no_entries)` / `Failure(:too_many_entries)`
  - default window: 6개월 (`DEFAULT_WINDOW_DAYS=180`, 한국 학기 분량) — `since`/`until` 명시 시 override
  - LLM 실패 시 결정적 fallback (Phase 11 패턴 동일) — 사용자에게 빈 결과보다 나음
  - audit `with_actor("agent")` 블록 — Thread-local 스택 활용 (Phase 11 합성기 패턴 그대로 확장)
  - top 학생 추출 — `entity_mentions ⨝ entities` 조인 (Phase 11 W17-T01 인프라 재사용)
  - spec 14건 (결정적 4 + 가드 3 + LLM 4 + 엣지 3): 학기 시뮬레이션 / frontmatter 8키 / 5 섹션 / 월별 청크 시간순 / since-until 기본값 / 6번 backend.chat 호출 / LLM 실패 fallback / 멱등 / vault 파일 누락 graceful
  - 회귀: 1095 → 1109 (+14). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.

### Phase 11 (Tier-1 LLM 합성) 완료 (W17-T01 ~ T04, 2026-05-10)
- **W17-T04 완료** (2026-05-10): 합성 결과 검토 UI — `/synth` 라우트 + 수락/거절
  - `Sowing::Controllers::SynthController` — 5 라우트
    - `GET /synth` — 디제스트 카드 목록 (LLM 합성 배지·모델 라벨·합성 시각·출처 수)
    - `GET /synth/students/:slug` — 디제스트 상세 (마크다운 → HTML 렌더 + 메타 dl)
    - `POST /synth/students/:slug/generate` — `SynthesizeStudentDigest` 호출 + audit `:synth_generate`
    - `POST /synth/students/:slug/accept` — `Domain::Record` 변환 + `Persistence#persist!` (audit `:create` + `:synth_accept` 2 줄) + 30_Records/{YYYY}/학생기록/ 으로 보존 + synth 원본 unlink
    - `POST /synth/students/:slug/reject` — `VaultRepo#delete` (휴지통 mv) + audit `:synth_reject`
  - `AuditLog::ALLOWED_ACTIONS` 확장: `:synth_generate`, `:synth_accept`, `:synth_reject` (Phase 11~12 fine-tuning preference 데이터)
  - 명시적 사용자 클릭 게이트 — 모든 변환은 confirm 다이얼로그 + 폼 submit (자율 mutation 0)
  - "LLM 합성" 배지 + 합성 모델 라벨 명시 — 사용자 글과 명확 구분 (의인화 카피 0)
  - 본문 영역 `synth-detail__warn` — "수락 시 정식 기록으로 이동" 경고
  - `views/synth/{index,show}.erb` + `.synth-*` CSS (배지·카드·메타·버튼)
  - `config/routes.rb` 마운트 (Settings 다음)
  - spec 10건: 목록 빈 상태 + 카드 + 배지 / 상세 + 마크다운 / 404 / accept (Record 생성 + 2 audit + synth 제거) / reject (휴지통 + audit) / generate (audit) / ADR-013 자율 mutation 0 검증
  - 회귀: 1085 → 1095 (+10). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.
- **W17-T03 완료** (2026-05-10): GapDetector (결정적, LLM 미사용)
  - `Sowing::UseCases::DetectStudentGaps` — class_roster vs 활성 entities (last_seen_at >= now - weeks_back × 7d) 비교
  - 결과: `{unmentioned, mentioned, roster_size, gap_ratio, since, weeks_back}` 멱등 결정적
  - Settings 키 `class_roster` (default `[]`) 추가
  - Settings 화면 "👥 학급 명단" 섹션 — 줄바꿈/쉼표 구분 입력, 중복·공백 자동 제거, 개인정보 보호 안내
  - Dashboard 카드 (gap-card):
    - 명단 미설정 → 안내 (gap-card--prompt, 녹색)
    - 미언급 0 → 카드 미표시
    - 미언급 N>0 → 빨간색 알림 카드 + `<details>` 로 학생 명단 표시
  - weeks_back 인자 (기본 4) — 활성 기준 조정 가능
  - ADR-013 거부 5종 준수: LLM 0, 결정적, 학생 익명성 안내 (가상명 권장)
  - spec 19건 (use case 12 + dashboard 3 + settings 4)
  - 회귀: 1066 → 1085 (+19). lint clean. `rake eval:run` 회귀 0.
- **W17-T02 완료** (2026-05-10): StudentDigest 합성기
  - `Sowing::UseCases::SynthesizeStudentDigest` — entity 조회 → mention된 entries 인용 → 디제스트 생성
  - 두 모드:
    - **결정적**: timeline + 인용 모음 (mode 아이콘 💭/📝/📖, vault path `[[wikilink]]` 출처)
    - **LLM 옵트인**: 변화·패턴·후속 과제 분석 (한국어 prompt, "추측 금지·인용 보존" 톤 안내)
  - 저장: `vault/.sowing/synth/students/{이름}.md` (`.sowing/` prefix → watcher 인덱싱 회피, 사용자 수동 검토 후 일반 entry 위치로 이동 가능)
  - frontmatter 6키: `is_synth: true` / `synth_target` / `synth_at` / `synth_source_count` / `synth_model` / `title`
  - SafeWriter atomic write (W1 동일 패턴) → 멱등, 중간 상태 없음
  - LLM 모드 audit log: `with_actor("agent")` 블록 — Phase 11+ 모든 합성 use case 동일 패턴
  - graceful: LLM 실패 → 결정적 fallback / vault 파일 사라진 경우 빈 excerpt
  - 익명 backend (`Class.new(Base)`) 도 작동하도록 `Backends::Base#name` 보강
  - spec 14건 (결정적 4 + LLM 4 + 엣지 5 + ROADMAP "민준" 시나리오 1)
  - 회귀: 1052 → 1066 (+14). lint clean. `rake eval:run` 회귀 0.
- **W17-T01 완료** (2026-05-10): EntityExtractor + entities 테이블
  - migration 006: `entities` (type/name UNIQUE, first/last_seen_at, mention_count) + `entity_mentions` (entity_id ↔ entry_id 다대다)
  - `Sowing::UseCases::ExtractEntities` — 두 모드:
    - **결정적**: KNOWN_STUDENT_NAMES whitelist (30개 한국 흔한 인명) + 조사 패턴 (받침 있음 "이X" / 받침 없음 직접) + SUBJECTS·LOCATIONS 사전 매칭
    - **LLM 옵트인**: `Backends::Base` 주입 시 한국어 NER prompt → JSON 파싱 (실패 시 결정적 fallback)
  - `AuditLog.with_actor("agent")` 통합 — Phase 9 thread-local 스택 활용
  - 멱등: 같은 entry 재호출 시 mention 중복 추가 안 함, mention_count 만 증가
  - **결정적 모드 한계 인정**: 한국어 NER 없이 인명 vs 일반 명사 구분 불가 → whitelist 외 이름은 LLM 모드에서만 추출 가능 (명시적 trade-off, ADR-013 거부 5종 위반 없음)
  - spec 13건 (ent-001~003 시드 + DB 저장 멱등 + LLM mode + audit 통합 + corpus 회귀)
  - 회귀: 1039 → 1052 (+13). lint clean. `rake eval:run` 회귀 0.

### 🎯 Phase 10 (Eval Infrastructure) ✅ 완료 (W13-T01~T04, 2026-05-10)

**마일스톤 달성**: 임의 LLM 출력 1건 → 자동 점수 + 사유 산출. 모델 버전 변경 시 회귀 자동 측정. ADR-013 의 Phase 10 → 11 → 12 순서 의무 충족 — Phase 11 (LLM 합성) 진입 가능.

**Phase 10 산출물 요약**:
- 100건 한국어 교사 글 코퍼스 (hand_crafted 11 + generated 89, 6 task type)
- LLM-judge harness (Judge + Kappa + 4 백엔드: Fake/OpenAI/Anthropic/Ollama)
- CI eval (Runner + ResultStore + `rake eval:run` + GitHub Actions)
- 5 한국어 도메인 차원 (결정적 휴리스틱, LLM 미사용)
- 회귀: 946 → 1039 (+93 spec). lint clean. 5x stress 4-5/5.

- **W13-T04 완료** (2026-05-10): 한국어 도메인 특화 5 차원
  - `honorific_consistency` — 종결어미 일관성 (문장 분리 + 마지막 어절, "X니다" 우선 매칭)
  - `korean_date_format` — 한국식(YYYY년 M월 D일) vs ISO(YYYY-MM-DD) 혼용 비율
  - `student_anonymity` — 풀네임 노출 패널티 (성씨 + 이름 정확 2글자, 단어 경계 + 조사 lookahead)
  - `classroom_context` — K-12 교실 어휘 사전 24개 매칭 종류 수
  - `tag_korean` — 한글 태그(`#가-힣`) 종류 수
  - 결정적 self-consistency → kappa = 1.0 (ROADMAP ≥ 0.7 형식 충족). 진짜 사람-judge 카파는 Phase 11+ 사용자 데이터 모인 후.
  - spec 28건. 회귀 1011 → 1039 (+28). lint clean.
- **W13-T03 완료** (2026-05-10): CI eval 통합
  - `Sowing::Eval::Runner` — corpus 순회 + judge + summary (per-dim avg/min/max/n) + filter (only_task / limit) + synthesizer 주입 (Phase 11+ 합성기 미리보기)
  - `Sowing::Eval::ResultStore` — JSON 결과 영속화 + `compare_to_previous` (Δ < -threshold 면 regressed=true, 기본 0.5)
  - `rake eval:run` — `SOWING_EVAL_BACKEND` 환경 변수로 백엔드 선택, 차원별 평균 출력 + 회귀 비교 + 회귀 시 exit 1
  - `rake eval:list` — 누적 결과 조회
  - `.github/workflows/eval.yml` — PR/main push 트리거, FakeBackend 로 회귀 검사 + artifact 업로드 (30일)
  - `eval/results/baseline-fake-backend.json` — 100건 baseline 커밋, 그 외 결과는 selective .gitignore (artifact 전용)
  - end-to-end: 100건 평가 → 11 차원 baseline + 회귀 비교 동작 ✓
  - spec 16건 (Runner 7 + 실제 100건 회귀 1 + ResultStore 8). 회귀 995 → 1011 (+16).
- **W13-T02 완료** (2026-05-10): LLM-judge harness
  - `Sowing::Eval::Judge` — case + LLM 출력 → 차원별 score 0~5 + reason. 12 차원 정의(SCHEMA.md §4 동기화). JSON 파싱 실패·차원 누락·범위 밖 score 모두 graceful fallback (clamp + 사유 명시)
  - `Sowing::Eval::Kappa` — Cohen's quadratic weighted + simple kappa. ordinal 점수에 적합. ROADMAP 검증 시나리오 (kappa ≥ 0.8) 통과
  - `Sowing::Eval::Backends::Base` 인터페이스 + 4 implementations:
    - `FakeBackend` — captured_prompts/responses 큐/baseline_json — CI 안전
    - `OpenAI` — Chat Completions (gpt-4o-mini 기본), Net::HTTP only
    - `Anthropic` — Messages API (claude-haiku-4 기본), system 별도 필드
    - `Ollama` — 로컬 (llama3.2 기본), ADR-013 "클라우드 강제 안 함" 직접 구현
  - Zeitwerk inflector "openai" → "OpenAI" 추가
  - 회귀 961 → 995 (+34 spec: Judge 14 + Kappa 9 + Backends 11). lint clean.
- **W13-T01 완료** (2026-05-10): 한국어 교사 글 eval 코퍼스 100건
  - `eval/corpus/SCHEMA.md` — 6 task type (entity_extraction / student_digest / gap_detection / reflection / contradiction / general) + 12 평가 차원 정의
  - `hand_crafted/` 11건 시드 + `generated/` 89건 자동 변형 = 100건
  - `eval/scripts/generate_corpus.rb` — 멱등 생성기 (Random.new(20260510) 고정 시드, 학생/과목/위치 치환)
  - contract spec 15건: 100건 정확, 6 task 모두 사용, case_id 고유·형식, 평가 차원 화이트리스트, hand_crafted 플래그 일치
  - 회귀: 946 → 961 (+15)

### 🎯 Phase 9 (Agent-Native Surface) ✅ 완료 (W9-T01~T05, 2026-05-09 / 마무리 2026-05-10)

**마일스톤 달성**: Claude Desktop/Codex/Continue/Zed 등에서 MCP 로 Sowing sensor·actuator 호출 가능. iPhone 17 문제도 ChatGPT 모바일 MCP 게이트웨이로 자연 해결 — 별도 iOS 앱 불필요.

**Phase 9 산출물 요약**:
- **12 MCP 도구**: sensor 4 (list_memos/search/read_entry/health) + actuator 4 (create_memo/note/record/promote) + analytics 4 (stats_summary/tag_cloud/wiki_complete/recent)
- **구조화 audit log** (`vault/.sowing/audit.log`): JSON Lines append-only, actor=user/agent/filesystem 구분, mutex 보호 thread-safe
- **AGENT_GUIDE.md**: 5분 셋업 + 12 도구 카탈로그 + 5 프롬프트 + 4 클라이언트 (Claude Desktop / Codex / Continue.dev / Zed)
- **bin/sowing-mcp**: stdio JSON-RPC 진입점 (공식 mcp gem v0.15 활용)
- **bin/sowing-doctor**: MCP / Audit 섹션 (도구 카운트·audit actor 분포·실행 권한 점검)

**검증**:
- 회귀: 855 → 946 (+91 spec). lint clean. 5x stress 0 failures.
- end-to-end stdio: `tools/list`, `tools/call create_memo` (실제 vault 마크다운 + audit `actor: "agent"`), `tools/call stats_summary` (한국어 GrowthStage label) 모두 정상.
- ADR-013 거부 5종 모두 준수: 챗봇 UI 0 / 자동 글쓰기 0 / 클라우드 강제 0 / 의인화 카피 0 / 자율 mutation 0.

**다음**: Phase 10 (Eval Infrastructure, W13~16) — LLM 기능 도입 전 검증 환경 구축. KICKOFF.md §P2.4 갱신.
- **W9-T05 완료** (2026-05-09): agent 지침 문서
  - `docs/AGENT_GUIDE.md` (~250줄) — 5분 빠른 시작 / 12 도구 카탈로그 / 5종 프롬프트 / 안전한 사용 패턴 / Troubleshooting
  - 4 클라이언트 설정 블록: Claude Desktop / Codex / Continue.dev / Zed
  - contract spec 10건: 12 도구 모두 문서화 검증 (새 도구 추가 시 가이드 갱신 강제)
  - 회귀: 936 → 946 (+10)
- **W9-T04 완료** (2026-05-09): MCP analytics sensors
  - 4개 read-only 도구 추가: `stats_summary` / `tag_cloud` / `wiki_complete` / `recent`
  - `stats_summary`: 오늘/주/월 카운트 + streak + 누적 + GrowthStage 5단계 (대시보드와 동일 데이터, AggregateDailyStats 자동 갱신)
  - `tag_cloud`: 사용 빈도 내림차순, limit 옵션
  - `wiki_complete`: ADR-004 위키링크 후보 (note/record title 매칭)
  - `recent`: 모드 통합 최근순 — 단일 모드인 `list_memos` 와 보완
  - 신규 `Sowing::Repositories::IndexRepo#recent_across` 메서드
  - Server::TOOLS: 8 → 12 (sensor 4 + actuator 4 + analytics 4)
  - end-to-end: stats_summary 호출 → growth.label "🌿 새싹" 한국어 라벨 정상
  - spec 18건. 회귀: 918 → 936.
- **W9-T03 완료** (2026-05-09): MCP write actuators
  - 4개 mutation 도구 추가: `create_memo` / `create_note` / `create_record` / `promote`
  - 모두 `AuditLog.with_actor("agent")` 블록으로 Use Case 호출 감쌈 → mutation 자동 actor=agent 마킹
  - `promote` 는 통합 도구 (`to: note|record`) — 메모→필기 또는 메모/필기→기록, ID 유지
  - 기존 Use Cases (CreateMemo/CreateNote/CreateRecord/PromoteToNote/PromoteToRecord) 그대로 재사용 — 새 비즈니스 로직 0
  - end-to-end: stdio JSON-RPC tools/call 한 번 → vault 마크다운 작성 + audit 1줄 검증
  - spec 16건. 회귀: 902 → 918.
- **W9-T02 완료** (2026-05-09): MCP 서버 stdio transport
  - 공식 `mcp` gem v0.15 채택 — zero-dep stdio, 깔끔한 DSL
  - `bin/sowing-mcp` 진입점 — Claude Desktop / Codex / ChatGPT 등록 가능
  - 4개 read-only sensor 도구: `list_memos`, `search`, `read_entry`, `health`
  - `Sowing::MCP.repositories` DI 싱글턴 — 테스트 격리 + 기본값 자동 폴백
  - end-to-end JSON-RPC 동작 검증 (initialize → tools/list → 4개 등록)
  - spec 24건 (server 6 + tools 18)
- **W9-T01 완료** (2026-05-09): 구조화 audit log
  - `Sowing::Infrastructure::AuditLog` — JSON Lines append-only, mutex 보호, 스레드 안전
  - 스키마: `{ts, actor, action, entry_id, mode, path, old_hash, new_hash}`
  - actor: `user` / `agent` / `filesystem` (W9-T03 MCP 에서 `agent` 활용 예정)
  - action: `:create` / `:update` / `:delete` / `:adopt` / `:reindex`
  - `Persistence#persist!` → `:create`, `#repersist!` → `:update`, 새 `#unpersist!` → `:delete`
  - `AdoptOrphan` → `:adopt` (actor=filesystem), `ReindexEntry` → `:reindex` / `:delete` (actor=filesystem)
  - `DeleteSamples` 가 새 `unpersist!` 사용
  - `AuditLog.with_actor("agent") { ... }` 블록 API — 중첩 가능, ensure 복원
  - spec 23건 추가 (단위 14 + 통합 9)

### Phase 2 방향성 결정 (2026-05-09)
- [`sowing-docs/EVALUATION.md`](sowing-docs/EVALUATION.md): Karpathy의 Sequoia Ascent 2026 12 명제로 Sowing 점검 — agent-native 데이터 레이어는 강함, agent-facing 표면(MCP·LLM 합성)은 비어 있음
- [`docs/DECISIONS.md`](docs/DECISIONS.md) ADR-013: Phase 2 (W9~W24, 16주)는 Software 3.0 전환에 헌정 — Phase 9 MCP / Phase 10 Eval / Phase 11~12 LLM 합성
- [`ROADMAP.md`](ROADMAP.md): Phase 2 작업 분해 추가 (W9-T01~W21-T04)
- [`KICKOFF.md`](KICKOFF.md) "Phase 2 진입자 안내" 추가 — 다음 세션 첫 30분 가이드
- 명시적 거부 5종: 챗봇 UI 금지 / 자동 글쓰기 거부 / 클라우드 LLM 강제 안 함 / 의인화 카피 안 씀 / 자율 에이전트 vault 변경 금지

### Added (W7+W8 wrap)
- 첫 실행 마법사 (`/onboarding`) — 4단계 (welcome → vault → profile → samples)
- 12종 샘플 콘텐츠 + `rake vault:seed` (협동학습 한 주 스토리, 위키링크 그래프 시연)
- 인터랙티브 튜토리얼 (`/tutorial`) — 3분 4단계, IndexRepo 카운트로 자동 진행 감지
- 동기화 가이드 (`/guides`) — iCloud / OneDrive / Dropbox / Syncthing
- 설정 화면 (`/settings`) — 프로필·경로·단축키·백업·샘플 정리·온보딩 재실행
- `bin/sowing-doctor` 강화 — 5+ 환경 점검 + 진단 요약 (W8-T06)
- `packaging/` Tebako 빌드 스캐폴드 (W8-T02)
- `bin/sowing dev`: rerun 의존 제거, rackup 직접 실행 (Ruby 4.0+ 호환)

## Phase 1 MVP 핵심 (W1~W6, 위 [0.1.0] 에 포함된 역사적 deliverable)

> 본 섹션은 v0.1.0 release 의 일부 — Phase 1 첫 6주에 작성된 핵심 기능 모음.
> [0.1.0] 위쪽 섹션이 Phase 9~12 + 확장·베타·패키징 등 *후속* 변경사항.

### Phase 1 — W1~W6 deliverables

### Domain & Storage
- Memo / Note / Record 3종 도메인 (메모 → 필기 → 기록 인지 모델)
- ULID 식별자 (정렬 가능, 옵시디언 호환)
- TagSet 정규화 (한국어 정렬, NFC, frozen)
- VaultRepo: write/read/list/delete(→trash)/update(path 이동) — 영구 삭제 금지
- IndexRepo + IndexedEntry: SQLite 메타 인덱스 (콘텐츠는 마크다운 SoT)
- SafeWriter: 원자적 쓰기 (tempfile + rename + fsync), NFC 정규화

### Web UI (Sinatra modular + Hotwire)
- 대시보드: 한국어 인사·날짜, 최근 메모 5건, 통계 카드(오늘/주/월), 🔥 streak, 🌱 씨앗-숲 시각화
- 메모 (`/memos`): 빠른 메모 모달(`Cmd+Shift+M`), Turbo Stream, 페이지네이션
- 필기 (`/notes`): CRUD, 카테고리 4종, 출처 필수, path 이동 시 휴지통
- 기록 (`/records`): CRUD, 자유 카테고리, datalist 자동완성
- 태그 (`/tags`): frontmatter ∪ 본문 `#태그` 자동 인덱싱, 태그 클라우드
- 검색 (`/search`): FTS5 trigram + 한국어 LIKE 폴백, 모드/카테고리/태그/날짜 AND
- 빠른 검색 (`Cmd+K`): 200ms 디바운스, ↑↓ 키보드 내비게이션
- 템플릿 (`/templates`): 시스템 12종 + 사용자 정의, `{{key}}` 치환

### Editor & Preview
- CodeMirror 6 마크다운 에디터 (line wrapping, 자동완성)
- 위키링크 자동완성 (`[[...]]`) + 태그 자동완성 (`#...`) — 200ms 디바운스
- 라이브 프리뷰 (좌-우 split, Turbo Stream, ~2ms 응답)

### Promotion (메모 → 필기 → 기록)
- ID 유지 + path 이동 + promoted_from frontmatter 자동
- 옛 파일은 휴지통 보존

### Sync (양방향, 옵시디언 호환)
- FileWatcher (Listen gem) — 외부 편집 감지
- SelfWriteRegistry — 자체 쓰기 필터 (TTL 2초, macOS realpath 정규화)
- ReindexEntry — mtime+hash 비교로 unchanged 단축
- AdoptOrphan — frontmatter 없는 외부 파일 자동 입양 (path 기반 mode 추론)
- Sync::Coordinator — watcher → reindex → adopt 폴백 파이프라인
- ConsistencyCheck — 부팅 시 볼트↔인덱스 검증 (인덱스 wipe → 자동 재구축)
- 충돌 처리 (Keep Mine / Keep Theirs / 취소) — 낙관적 잠금 + .sowing/conflicts/ 백업

### Statistics
- daily_stats 테이블 + AggregateDailyStats (KST 고정, 트랜잭션 멱등)
- StatsRepo: today / this_week(7일) / this_month / current_streak / total_all_time
- GrowthStage: 5단계 (empty/seed/sprout/tree/forest, 누적 0/1/10/50/150)

### CLI & Diagnostics
- `bin/sowing dev` (개발 서버, 자동 재시작)
- `bin/sowing memo "내용"` (CLI 빠른 메모)
- `bin/sowing-doctor` (환경·인덱스·동기화·학습·가이드 진단)
- `rake vault:seed` (12종 샘플 시드, ULID 중복 자동 skip)
- `rake vault:reindex` (ConsistencyCheck로 인덱스 재구축)
- `rake db:migrate` / `db:reset` / `db:setup`

### Quality
- 855건 RSpec 테스트 통과
- standardrb 린트 클린
- 5x 스트레스 0 failures

[Unreleased]: https://github.com/junkicho-lab/sowing/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/junkicho-lab/sowing/releases/tag/v0.1.0
