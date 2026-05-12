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

## 게이트 #3: Export 5종 우선순위

**결정일**: 2026-05-12
**결정**: **c — 5종 모두 MVP 포함** (비전 E.3 완전 충족, v0.2.0 +1주)

### 5 Template 모두 Stage 4b 에 포함

| Template | enum | 입력 | 출력 양식 |
|---|---|---|---|
| 📝 생기부 | `student_record` | 학생 mention + 학기 entries | 행동·교과·창체 영역별 |
| 💬 상담부 | `consultation` | 학부모 상담 + 학생 mention | 학생별 면담 이력 + 다음 준비 |
| 📑 회의록 | `meeting_minutes` | 회의 카테고리 + 날짜 | 일시·참석자·안건·결정·후속 |
| 💼 사업계획서 | `project_proposal` | 사업 카테고리 | 목표·일정·예산·기대효과 |
| 💰 예산요구서 | `budget_request` | 사업 + 비용 mention | 항목·단가·총액·근거 |

### 작업 분해 (Stage 4b 확장)

기존 권장 (P0 2종) 에서 5종 전체로 → Stage 4b 작업 +1 주.

R4b-T01 ~ R4b-T05: 각 use case + ERB template + PDF/DOCX export
R4b-T06: spec ~80 (template 별 16 case)

### 트레이드오프

- ✅ **비전 E.3 완전 충족** — 5 용도 모두 day 1 출시
- ✅ **양식 학교별 차이** — ERB template 사용자 편집 가능
- ⚠ **양식 검증 부담** — 5 template 모두 학교 실무 양식과 일치 검증 필요
- ⚠ **Stage 4b 가 8주 일정의 핵심 — 1주 추가** = 총 8주

→ #5 게이트의 C (8주) 와 정합.

---

## 게이트 #4: 기존 mode 폐기 가능성

**결정일**: 2026-05-12
**결정**: **a — Note 만 폐기**, 다른 mode·기능 모두 유지

### 최종 mode 매트릭스

| Mode | v0.1.8 → v0.2.0 | 비고 |
|---|---|---|
| 💭 Memo | **유지** (`Capture::Item`) | rename 만 |
| 📝 Note | **폐기** (`Knowledge::Record` 흡수) | 게이트 #1 |
| 📖 Record | **유지** (`Knowledge::Record`) | + subject + archive |
| 🗓 Plan | **유지** (`Knowledge::Plan`) | + subject + archive |
| 🌱 Synth (17종) | **유지** (`Insight::Synthesizer::*`) | namespace 이전 |
| 📋 Template (12 자유) | **유지** | 사용자 정의 영역 |
| 🎓 Tutorial | **유지** | 베타 후 v0.2.x 에서 단축 검토 |
| 🪄 Onboarding | **유지** | 동일 |
| (신규) | `Output::Template` 5종 | Export 양식 |

### 트레이드오프

- ✅ **변경 최소화** — Note 만 폐기, 다른 사용자 친숙한 영역 유지
- ✅ **자유 템플릿 12종 그대로** — 사용자 학교별 양식 정의 영역
- ⚠ **10_Templates/ 와 Output::Template 의 공존** — 명명 헷갈림 가능
  - 해결: `10_Templates/exports/*.erb` 로 Output 만 분리 (Stage 4b R4b-T02)
  - 기존 12 자유 템플릿은 `10_Templates/` 루트에 그대로

---

## 게이트 #5: 기간 추정

**결정일**: 2026-05-12
**결정**: **C — 8주 완전 (Strangler Fig 완주)** + Export 5종 → 실질 **8주**

### 일정 (확정)

| Week | 날짜 | Stage | 핵심 |
|---|---|---|---|
| W33 | 2026-05-19 | Stage 0 완료 + Stage 1 (R1) | 모듈 골격 + Façade |
| W34 | 2026-05-26 | Stage 2 (R2) | Capture 이전 + Subject migration |
| W35 | 2026-06-02 | Stage 3 (R3) 진입 | Knowledge·Record·Plan 이전 |
| W36 | 2026-06-09 | Stage 3 계속 | Archive + Subject UI + reclassify |
| W37 | 2026-06-16 | Stage 4a (R4a) | Insight 17 합성기 namespace |
| W38 | 2026-06-23 | Stage 4b (R4b) 진입 | Output Template 5종 (생기부·상담부) |
| W39 | 2026-06-30 | Stage 4b 계속 | 회의록·사업계획서·예산요구서 + PDF/DOCX |
| W40 | 2026-07-07 | Stage 5 (R5) — **v0.2.0 출시** | 폐기 + 검증 + tag push |

### 베타 인터뷰 시점 정합

```
2026-07-07  v0.2.0 출시 (Phase R 완료)
2026-07-08  ~ 2026-08-11  안정화·hotfix·문서 정비 (5주)
2026-08-12  베타 인터뷰 시작 (5명, v0.2.0 기준)
2026-08-16  인터뷰 마감
2026-08-25  Phase 18+ 진입 결정
```

### 트레이드오프

- ✅ **완전 모듈형** — 옛 코드 제거, 기술 부채 0
- ✅ **베타 인터뷰 5주 전 출시** — 안정화 시간 충분
- ✅ **Strangler Fig 완주** — 단계적 검증 가능
- ⚠ **개발 압박** — 8주 단일 개발자 (Claude + 사용자) full speed 필요
- ⚠ **Stage 4b 5종 → 모두 출시** — 양식 검증 압박 (베타 1인 검토 필수)

---

## Stage 0 합의 완료 — 다음 단계

5 게이트 모두 합의됨. 다음 작업 순서:

1. ✅ 본 문서 (REFACTORING_DECISIONS.md) 5건 모두 기록
2. **ADR-015 ~ ADR-019** 정식 등록 (docs/DECISIONS.md)
3. ROADMAP.md 에 Phase R (W33~W40) 항목 추가
4. `git tag pre-stage-1` 롤백 anchor
5. Stage 1 진입 — `[R1-T01] core/ 디렉토리 신설`

---

## 합의 결정 history

| 날짜 | 게이트 | 결정 |
|---|---|---|
| 2026-05-12 | #1 Note 정체성 | **B** — Note 폐기, Knowledge::Record 로 흡수 |
| 2026-05-12 | #2 Subject 4축 enum | `person · subject · document · identity` (충돌 의식 + 가이드라인) |
| 2026-05-12 | #3 Export 우선순위 | **c** — 5종 모두 MVP (Stage 4b +1 주) |
| 2026-05-12 | #4 추가 폐기 mode | **a** — Note 만 폐기, 다른 모두 유지 |
| 2026-05-12 | #5 기간 | **C** — 8주 완전 (Strangler Fig 완주, v0.2.0 = 2026-07-07) |
