# Refactoring 합의 결정 기록

> **목적**: REFACTORING_BLUEPRINT.md §7 의 사용자 합의 게이트 9건 의사결정 trace.
> **상태**: Stage 0 진행 중 (5건 중 2건 합의됨, 3건 PENDING)

---

## 게이트 #1: Note 의 정체성 (Stage 0)

**결정일**: 2026-05-12
**결정**: **B — Note 폐기, `Knowledge::Record` 로 흡수**

### 근거

- 사용자 비전 (MVP_VISION §B) 의 입력 자료 4종 = 메모·공부·보고서·계획서
- "공부" 와 "보고서" 의 경계가 사용자 의도상 모호 (둘 다 정리·체계)
- 옵션 A (분리) 는 도메인 객체 1개 추가 — Bounded Context 복잡도 증가
- 옵션 C (Note 유지 + Reference 로 통일) 는 의미 변경만 — rename 부담
- **B 가 가장 단순** + 사용자 비전과 정합

### 영향

- 기존 `Note` 도메인 → `Knowledge::Record` 로 흡수
- 기존 `20_Notes/{카테고리}/*.md` 파일 → `30_Records/{YYYY}/{카테고리}/*.md` 로 이전
- 마이그레이션: 모든 note row 의 mode 를 'note' → 'record' (단, 위험 — Stage 5 폐기 단계에서)
- Strangler Fig: Stage 4 까지 Note 는 alias 로 작동 (`Knowledge::Note = Knowledge::Record`)
- 사용자 UX: 'note 작성' 진입점 ('필기 작성') → 'record 작성' ('기록 작성') 으로 통합
- 도메인 변경 영향: VaultRepo·IndexRepo·합성기 17종·view·spec ~50건 영향

### 트레이드오프 인지

- ✅ **단순함** — 4 mode → 3 mode (Memo·Record·Plan)
- ✅ **사용자 비전 정합** — 비전엔 "필기" 라는 별도 mode 없음
- ⚠ **기존 사용자 노트 마이그레이션** — 자동 변환 + 사용자 검토 단계 필수
- ⚠ **카테고리 분류 부담 증가** — 메모 → 바로 record (필기 단계 생략 — 의도된 단순화)

### Stage 6 재검토 게이트

Stage 2 끝 (Capture 완료) 후 #6 게이트로 재확인. Capture 가 메모를 더 풍부하게 만들었다면 Note 의 필요성이 더 약해질 가능성.

---

## 게이트 #2: Subject 4축 enum 명명 (Stage 0)

**결정일**: 2026-05-12
**결정**: ENUM 값 = `person · subject · document · identity`

### 4축 매핑

| 비전 분류 (한글) | enum 키 | emoji | 의미 |
|---|---|---|---|
| 👤 인물 | `:person` | 👤 | 학생·교사·학부모·동료 |
| 📚 교과 | `:subject` | 📚 | 수업·평가·문항출제·차시 |
| 📋 계획서 | `:document` | 📄 | 행사·회의·사업·연수계획 |
| 🧭 정체성 | `:identity` | 🧭 | 교육목표·교육과정·교육철학·자기회고 |

### 명명 충돌 의식

⚠ **주의**: `:subject` 가 4축 분류 이름 ("주제 분류") 과 동일.

| 컨텍스트 | 의미 |
|---|---|
| "Subject 4축" (개념) | 4 enum 의 전체 분류 axis |
| `entry.subject` (DB column) | 하나의 enum 값 |
| `entry.subject == :subject` | 교과 의미 (4축의 두 번째 값) |

### 충돌 회피 가이드라인 (코드·문서)

#### 코드 컨벤션

```ruby
class Sowing::Knowledge::Domain::Record
  # 4축 분류 — 사용자 비전의 'D. 판단 기준'
  SUBJECT_AXES = %i[person subject document identity].freeze

  attr_reader :subject  # SUBJECT_AXES 의 하나 또는 nil
end

# 사용 시 의미 명확:
record.subject == :person   # 인물 분류
record.subject == :subject  # 교과 분류 (충돌 — 주석 명시 권장)
```

`:subject == :subject` 같이 헷갈리는 표현은:

```ruby
# ❌ Bad: 의미 불명확
if entry.subject == :subject

# ✅ Good: 의미 명시
if entry.subject == :subject # 교과 분류
# 또는 상수로:
CURRICULUM_SUBJECT = :subject
if entry.subject == CURRICULUM_SUBJECT
```

#### 문서 컨벤션

- "Subject 4축" — 4 enum 의 전체 분류 (영문 표기)
- "주제 분류" / "분류 축" — 한글 표기 (개념 자체)
- "교과" (한글) / `:subject` enum 키 — 두 번째 값 (충돌 의식)
- "인물" / `:person`, "계획서" / `:document`, "정체성" / `:identity`

#### UI 컨벤션

- 사용자 노출: 한글 ("인물·교과·계획서·정체성")
- URL 쿼리: enum 키 ("?subject=person")
- 코드: enum symbol

### Phase 15 작업 영향

- Migration 008: `entries.subject` column (CHECK 제약: `IN ('person', 'subject', 'document', 'identity')`)
- Domain: SUBJECT_AXES 상수 + validate_subject_axis!
- UI: subject chip 4개 (인물·교과·계획서·정체성 라벨)
- Filter: `/view/recent?subject=person` 등 4 chip
- reclassify 도구: 카테고리 → axis 자동 제안 매핑

### 자동 분류 추천 매핑 (사용자 검토 필요)

| 기존 카테고리 (자유) | 자동 제안 subject |
|---|---|
| 학생기록·상담·학생관찰 | `:person` |
| 수업·수업회고·평가·도덕·도덕수업 | `:subject` |
| 회의·행사·사업·학급운영·trainings | `:document` |
| 학기회고·자기회고·교육철학 | `:identity` |
| books·meetings (기타) | 사용자 직접 |

Stage 3 R3-T11 (reclassify 도구) 가 위 매핑으로 제안 → 사용자 일괄 검토 + 적용.

---

## 게이트 #3: Export 5종 우선순위 (PENDING)

**Stage 0 미합의**.

사용자 결정 필요:

```
P0 (MVP 필수):  ?? 종
P1 (MVP+1):    ?? 종
P2 (MVP+2):    ?? 종
```

권장 옵션:

| Template | 사용자 권장 우선순위 | 이유 |
|---|---|---|
| 📝 생기부 | **P0** | 매 학기말 의무, 베타 테스터 핵심 needs |
| 💬 상담부 | **P0** | 매 학기 진행, 학생별 누적 |
| 📑 회의록 | P1 | 학교 양식 차이 큼, 학기 1~2회 |
| 💼 사업계획서 | P1 | 연 1회 큰 문서, 양식 표준화 어려움 |
| 💰 예산요구서 | P2 | 사업계획서 후속, 양식 차이 더 큼 |

권장 결정:
- **P0 = 생기부 + 상담부** (학생 중심)
- **P1 = 회의록 + 사업계획서** (학교 운영)
- **P2 = 예산요구서** (선택)

→ Stage 4b (Output) 의 use case 5개 중 2개만 MVP, 3개는 v0.2.0 후 추가 출시.

---

## 게이트 #4: 기존 mode 폐기 가능성 (PENDING)

**Stage 0 미합의**.

게이트 #1 의 B 결정으로 Note 는 폐기 확정. 추가 검토:

| Mode | 현재 사용 | 폐기 검토 |
|---|---|---|
| 💭 Memo (00_Inbox) | ✅ 매일 입력 | 유지 (Capture::Item) |
| 📝 Note (20_Notes) | 사용자 결정 B | **폐기** (Knowledge::Record 흡수) |
| 📖 Record (30_Records) | ✅ 30년 누적 | 유지 (Knowledge::Record) |
| 🗓 Plan (40_Plans) | ✅ 미래 계획 | 유지 (Knowledge::Plan) |
| 🌱 합성 (.sowing/synth) | ✅ 17종 | 유지 (Insight::Synthesis) |
| 📋 Template (10_Templates) | 자유 마크다운 | 유지 + Output::Template 확장 |

추가 폐기 후보 (사용자 의견 필요):
- ❓ `10_Templates/` 의 기존 12 자유 템플릿 — Output::Template 5종으로 통합 vs 별도 유지?
- ❓ Tutorial mode — 베타 후엔 단축할 수 있음?
- ❓ Onboarding 마법사 — 새 mode 가 단순해지면?

권장:
- **Note 만 폐기** — 다른 mode 모두 유지
- **10_Templates/** 의 자유 템플릿은 별도 유지 (사용자 정의 영역)
- Tutorial·Onboarding 은 v0.2.0 후 검토

---

## 게이트 #5: 기간 추정 6주 vs 8주 (PENDING)

**Stage 0 미합의**.

권장 분기:

| 시나리오 | 기간 | 트레이드오프 |
|---|---|---|
| **A. 6주 (최소)** | Phase R3 + R4b 만 (사용자 가치 직접) | Phase R1·R2·R4a 의 순수 리팩토링 생략. v0.2.0 출시 빠름 but 기술 부채 잔존. |
| **B. 7주 (균형)** | Phase R3 + R4b + R1 (모듈 골격) | Bounded Context 만 도입, 옛 Memo·Record 그대로. |
| **C. 8주 (완전)** | Phase R1~R5 모두 (Strangler Fig 완주) | 완전 모듈형, 옛 코드 제거. 기술 부채 0. |

권장:
- 베타 인터뷰 (2026-08-12) 직전 v0.2.0 출시 가능 — 8주 완전 진행 시 2026-07-07 출시 → 1개월 안정화 기간 확보
- **C (8주)** 권장 — 완전 모듈형 + 안정화 시간 충분

---

## 합의 미합 상태 — 다음 단계

남은 3 게이트 (#3·#4·#5) 답변 받으면:

1. 본 문서 갱신 (PENDING → 결정)
2. **ADR-015 ~ ADR-019** 정식 초안 작성 (docs/DECISIONS.md)
3. `git tag pre-stage-1` (롤백 anchor)
4. Stage 1 첫 commit `[R1-T01] core/ 디렉토리 신설`

---

## 합의 결정 history

| 날짜 | 게이트 | 결정 |
|---|---|---|
| 2026-05-12 | #1 Note 정체성 | **B** — Note 폐기, Knowledge::Record 로 흡수 |
| 2026-05-12 | #2 Subject 4축 enum | `person · subject · document · identity` (충돌 의식 + 가이드라인) |
| pending | #3 Export 우선순위 | — |
| pending | #4 추가 폐기 mode | — |
| pending | #5 기간 6/7/8주 | — |
