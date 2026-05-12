# Sowing 🌱 MVP 제품 설명서 — 비전 vs 현재

> **작성일**: 2026-05-12
> **현재 버전**: v0.1.8
> **목적**: 사용자가 추구하는 비전 (A~E) 과 현재 Sowing 의 gap 분석 + MVP 정의

---

## 1. 비전 (사용자 정의)

> **A.** 교사들이 30년간 자기 경험과 통찰을 **기록·보관·활용·전달** 할 수 있는 앱
> 미래의 나와 동료에게 전달.
>
> **B.** 입력 자료: 메모·공부자료·보고서·계획서
>
> **C.** 처리 흐름: 매일 입력 → 평상시 사용 → 이벤트 시 간헐 → 학기/학년말 공식 문서 →
> 대상학생/학년도 지나면 **이관** → 필요시 검색
>
> **D.** 판단 기준 (4축): **인물 · 교과 · 계획서 · 정체성**
>
> **E.** 출력 모드 (3축): **시간적 · 주제별 · 용도별**

---

## 2. 비전 vs 현재 Sowing — Gap Analysis

### A. 30년 누적 + 전달

| 요소 | 비전 | Sowing v0.1.8 | Gap |
|---|---|---|---|
| 30년 보존 | ✅ 핵심 | ✅ `30_Records/{YYYY}/` + 카테고리 × 연도 매트릭스 | 없음 |
| 자기 통찰 | ✅ | ✅ 17 합성기 + 자기 거울 5축 | 없음 |
| **동료 전달** | ✅ 핵심 | ⚠ vault 폴더 통째로 공유 가능 (옵시디언) — 별도 export 없음 | **공식 인계 export 필요** |

### B. 입력 자료 4 종

| 비전 | Sowing 매핑 | 평가 |
|---|---|---|
| 메모 (생각·느낌) | 💭 메모 (`00_Inbox`) | ✅ 동일 |
| 공부 내용·자료 | 📝 필기 (`20_Notes`) | ⚠ "공부" 라는 분류는 카테고리 자유 — 명시 mode 아님 |
| 보고서 | 📖 기록 (`30_Records`) | ⚠ 보고서 양식 (제목·서론·본론·결론) 별도 X |
| 계획서 | 🗓 계획 (`40_Plans`) | ✅ Phase 13 W27 신설 |

### C. 처리 흐름 5단계

| 단계 | 비전 | Sowing 현재 | Gap |
|---|---|---|---|
| 매일 입력 | ✅ | ✅ `⌘⇧M` + subtype + 음성 | 없음 |
| 평상시 사용 | ✅ | ✅ 검색·태그·그래프·매트릭스 | 없음 |
| 이벤트 시 간헐 | ✅ | ✅ 17 합성기 옵션 호출 | 없음 |
| **학기/학년말 공식 문서** | ✅ 핵심 | ⚠ 학기 회고·평가 누적 등 합성기는 있지만 **공식 양식 export** 없음 | **양식별 template 필요** |
| **대상학생/학년도 이관** | ✅ 핵심 | ❌ archive mode 없음 — 모든 데이터 active 상태 | **Archive mode 신설** |

### D. 판단 기준 4축

| 4축 | Sowing 현재 분류 매핑 | Gap |
|---|---|---|
| 👤 **인물** (학생·교사·학부모) | entity_mentions 시스템 (학생만 명시) | ⚠ 교사·학부모 entity 미흡, 4축 통합 X |
| 📚 **교과** (수업·평가·문항출제·분석) | 카테고리 `lessons/수업/수업회고/평가` 자유 | ⚠ 4축 명시 분류 X, "문항출제·분석" 전용 mode X |
| 📋 **계획서** (행사·회의·사업추진) | `40_Plans/` mode 존재 | ⚠ Plan 은 시간 단위 (daily/weekly...) — 종류 (행사/회의/사업) 분류 X |
| 🧭 **정체성** (목표·과정·철학) | 자유 카테고리 — 명시 분류 없음 | ❌ **신설 필요** — 학기·학년 의 큰 흐름 정리 mode |

**결론**: 현재 Sowing 은 **시간 (mode) + 카테고리 (자유)** 두 축. 비전의 **4축 주제 분류** 는 부분적으로만 자유 카테고리에 들어감.

### E. 출력 모드 3축

| 출력 축 | 비전 | Sowing 현재 |
|---|---|---|
| **시간적** (오늘/주/달/학기/년/기간선택) | ✅ | ⚠ 오늘/주/달/timeline ✅, **학기·학년 단위 명시** + **기간 선택 UI** ⚠ |
| **주제별** (인물/교과/계획서/정체성) | ✅ | ⚠ 카테고리 chip 은 있지만 **4축 매핑** 안 됨 |
| **용도별** (생기부/상담부/회의록/사업계획서/예산요구서) | ✅ | ❌ **공식 문서 양식 출력 전혀 없음** |

---

## 3. Gap 우선순위 매트릭스

| Gap | 비전 핵심성 | 현재 부재 정도 | MVP 우선순위 |
|---|---|---|---|
| 4축 주제 분류 (인물/교과/계획서/정체성) | 🔴 핵심 | 🟡 부분 (카테고리 자유) | **🔴 P0 (MVP 필수)** |
| 용도별 출력 (생기부/상담부/회의록/사업계획서/예산요구서) | 🔴 핵심 | 🔴 없음 | **🔴 P0 (MVP 필수)** |
| Archive mode (졸업·학년종료 이관) | 🔴 핵심 | 🔴 없음 | **🔴 P0 (MVP 필수)** |
| 학기/학년 시간 단위 명시 | 🟡 보강 | 🟡 부분 | 🟡 P1 |
| 교사·학부모 entity | 🟡 보강 | 🟡 학생만 | 🟡 P1 |
| 동료 전달 export | 🟡 보강 | 🟡 vault 공유 | 🟢 P2 |
| 보고서 양식 (서론·본론·결론) | 🟢 nice-to-have | 🟢 자유 마크다운 | 🟢 P2 |

---

## 4. MVP 정의

### 4.1 MVP 의 목표

> **현재 Sowing v0.1.8 의 인프라 (30년 누적·17 합성기·동사 IA·계획 mode) 를 그대로 유지하면서, 사용자 비전의 4축 분류 + 용도별 출력 + 이관 처리 를 추가**.

### 4.2 MVP 의 3 핵심 변화

```
┌─────────────────────────────────────────────────────────┐
│ Δ1. Subject 4축 (인물·교과·계획서·정체성)               │
│     → 모든 entry 에 subject 메타 추가                   │
│     → 카테고리 (자유) 와 별도 축 (제약된 4종)           │
│                                                          │
│ Δ2. 용도별 Template Export (5종 + 확장)                 │
│     → 생기부·상담부·회의록·사업계획서·예산요구서        │
│     → 선택 entries 또는 자동 합성 → 공식 양식 출력      │
│                                                          │
│ Δ3. Archive Mode (이관 처리)                            │
│     → 졸업 학생 / 종료 학년도 별 아카이브 폴더          │
│     → 검색 가능하되 일상 회상에서 자동 제외             │
│     → 명시적 unarchive 가능                             │
└─────────────────────────────────────────────────────────┘
```

### 4.3 MVP scope — 비전 vs MVP

| 비전 요소 | MVP 포함? | 이유 |
|---|---|---|
| **4축 (인물·교과·계획서·정체성)** | ✅ MVP | 모든 출력의 기반 |
| **용도별 5종 (생기부 등)** | ✅ MVP | 비전 E.3 직접 충족 |
| **Archive (이관)** | ✅ MVP | 30년 누적이 무거워지면 일상 회상 방해 |
| 학기·학년 시간 단위 | 🟡 MVP+1 | 합성기는 이미 있음, UI 명시화만 |
| 교사·학부모 entity | 🟡 MVP+1 | 4축 인물 안에서 부분 충족 |
| 보고서 양식 | 🟢 MVP+2 | 자유 마크다운으로 충분 |
| 동료 전달 export | 🟢 MVP+2 | vault 공유로 부분 충족 |

---

## 5. MVP 상세 설계

### 5.1 Δ1: Subject 4축 분류 (가장 큰 변화)

#### 데이터 모델

**Memo / Note / Record / Plan 도메인** 에 `subject` 필드 추가:

```ruby
class Memo / Note / Record / Plan
  # 기존: id, body, tags, title, category, ...
  # 신규: subject (4축 중 1개 또는 nil)
  attr_reader :subject  # :person | :curriculum | :plan | :identity | nil
end
```

#### 4 subject 정의

| Subject | 영문 키 | 포함하는 카테고리·키워드 예시 |
|---|---|---|
| 👤 **인물** | `person` | 학생기록·상담·학부모·동료·학생관찰 |
| 📚 **교과** | `curriculum` | 수업·수업회고·평가·도덕·문항·차시 |
| 📋 **계획서** | `plan_doc` | 행사·회의·사업·연수계획·학급운영 |
| 🧭 **정체성** | `identity` | 교육목표·교육과정·교육철학·학기회고·자기회고 |

#### Subject vs 기존 category 관계

```
subject (제약된 4축)   ←   상위 분류 (대분류, 4 enum)
   ↓
category (자유 텍스트) ←   하위 분류 (소분류, 사용자 정의)
   ↓
tags (자유 #tag)        ←   횡단 색인
```

예시:
- `subject: curriculum, category: 수업회고` → 교과 / 수업회고
- `subject: person, category: 학생기록, tag: #민준` → 인물 / 학생기록 / 민준
- `subject: identity, category: 학기회고` → 정체성 / 학기회고

#### DB 변경 (마이그레이션 008)

```ruby
Sequel.migration do
  change do
    alter_table(:entries) do
      add_column :subject, String  # nullable — 기존 entry 호환
      add_index :subject
    end
  end
end
```

CHECK 제약 추가 (선택): `CHECK (subject IN ('person', 'curriculum', 'plan_doc', 'identity') OR subject IS NULL)`

#### UI 변경

- 빠른 메모 모달: subtype chip 5개 → **subject chip 4개 + subtype chip** (2단계)
- 필기/기록 작성: 카테고리 선택 위에 **🔵 Subject 4축 라디오** 추가
- 필터: `/view/recent?subject=person` 같은 query 지원
- 카테고리 × 연도 매트릭스 → **Subject × 연도 매트릭스** 추가 (병행)

### 5.2 Δ2: 용도별 Template Export (5종 + 확장)

#### MVP 5 template

| 용도 | 입력 (자동 수집) | 출력 양식 |
|---|---|---|
| 📝 **생기부** | 인물·학생 mention + 학기 entries | 학생별 1 페이지 (행동·교과·창체) |
| 💬 **상담부** | 인물·학부모 상담 mention | 학생별 면담 이력 + 다음 면담 준비 |
| 📑 **회의록** | 계획서·회의 (특정 날짜) | 일시·참석자·안건·결정·후속 |
| 💼 **사업계획서** | 계획서·사업 카테고리 | 목표·일정·예산·기대효과 |
| 💰 **예산요구서** | 계획서·사업 + 비용 mention | 항목·단가·총액·근거 |

#### 신규 라우트

```
GET  /export                          # 5 template 선택 화면
GET  /export/student-record/:name     # 생기부 — 학생 선택 → 양식
GET  /export/consultation/:name       # 상담부 — 학생별
GET  /export/meeting/:date            # 회의록 — 날짜 선택
GET  /export/project/:slug            # 사업계획서 — 프로젝트 선택
GET  /export/budget/:slug             # 예산요구서 — 사업 연계
POST /export/:type → PDF·DOCX·MD 다운로드
```

#### Export 동작 흐름

```
1. /export 진입 → 5 template chip
2. 사용자가 '생기부' 선택 → 학생 이름 입력
3. 시스템: 해당 학생 entity_mentions 모든 entries 수집
   + subject=person 필터 + 기간 (학기 default)
4. 양식 적용:
   - 행동 영역 (학생 관찰 메모 요약)
   - 교과 영역 (subject=curriculum + 학생 mention)
   - 창체 영역 (계획서 + 학생 참여)
5. 마크다운 → HTML → PDF 또는 DOCX 다운로드
6. LLM 옵션: 단정 거부 톤으로 자연어 요약 (수락 후 정식)
```

#### Template 정의 파일

```
10_Templates/exports/
├── student-record.md.erb      # 생기부 양식
├── consultation.md.erb        # 상담부
├── meeting.md.erb             # 회의록
├── project.md.erb             # 사업계획서
└── budget.md.erb              # 예산요구서
```

사용자가 ERB template 직접 편집 가능 (학교별 양식 차이).

### 5.3 Δ3: Archive Mode (이관 처리)

#### 데이터 모델

`entries` 테이블에 `archived_at` (ISO8601) + `archive_reason` (text) 추가:

```ruby
add_column :archived_at, String  # nil = active, ISO8601 = archived
add_column :archive_reason, String  # '졸업', '학년종료', '사업종료', 사용자 정의
add_index :archived_at  # IS NULL / IS NOT NULL 빠르게
```

폴더 구조 변경 없음 — `30_Records/{YYYY}/{카테고리}/...` 그대로. archive 는 메타데이터만.

#### Archive UI

```
새 1급 메뉴 (또는 ⚙ 설정 → 데이터):
🗄 보관함 (Archive)
├── 학생별 (졸업)        예: 2024년 졸업생 3-7반
├── 학년도별 (종료)      예: 2024 학년도 (subject=person 인 entries)
├── 사업·프로젝트별      예: 2024 영재교실 사업
└── 자유 (수동 archive)  예: 옛 학교 데이터
```

#### Archive 동작

1. **이관 액션**:
   - 학생 이름 + 기간 → 해당 학생 mention 모든 entries archive
   - 학년도 (예: 2024) → 그 해 모든 entries archive (선택적: 인물·정체성만)
   - 수동: 개별 entry 의 'archive' 버튼

2. **Archive 후 동작**:
   - `/view/recent` / 검색 / 합성기 등 **일상 회상에서 자동 제외** (`archived_at IS NULL` 필터)
   - 보관함 (`/archive`) 에서만 접근
   - 검색 시 옵션 'archive 포함' 체크박스 (default OFF)

3. **Unarchive**:
   - 사용자 명시 클릭 → `archived_at = nil` + flash 안내
   - audit log 에 기록 (ADR-013)

#### 30년 시나리오의 의미

```
0~5년차: 모든 entries active
6년차:   2020년 학생들 졸업 → archive
10년차:  매년 1 학년도씩 archive (자동 제안)
20년차:  active = 최근 5~10 학년도만, archive = 그 이전 모두
30년차:  필요시 archive 검색 → 옛 학생 보고서 작성 등
```

**핵심 가치**: 30년 누적이 무거워져도 **일상 UX 가 가벼움** 유지.

---

## 6. 변경 영향 매트릭스

### 6.1 핵심 코드 변경

| 영역 | 파일 (예상) | 변경 규모 |
|---|---|---|
| Domain | `lib/sowing/domain/{memo,note,record,plan}.rb` | subject + archived_at 추가 |
| Migration | `db/migrations/008_add_subject_archive_to_entries.rb` | 신규 |
| Repository | `index_repo.rb` | upsert + 필터 + archive 메서드 |
| Use Case | `create_*.rb` | subject 인자 |
| Use Case | `archive_entry.rb`, `unarchive_entry.rb` | 신규 |
| Use Case | `export_*.rb` | 5종 신규 (생기부 등) |
| Controller | `archive_controller.rb`, `export_controller.rb` | 신규 |
| View | `views/archive/*`, `views/export/*` | 신규 |
| Template | `10_Templates/exports/*.md.erb` | 5종 신규 |
| Nav | layout — Archive + Export 추가 | dropdown 항목 추가 |

### 6.2 Subject 4축의 모든 표면

- 메모 입력 모달 (chip 4 개)
- 필기·기록·계획 작성 폼 (라디오 4)
- /view/recent 필터 (chip 4)
- 카테고리 × 연도 매트릭스 → Subject × 연도 매트릭스 옵션
- 검색 결과 subject 별 facet
- 합성기 입력 필터 (예: 학기 회고 → subject=identity 만)
- 자기 거울 5축 중 "관계" → subject=person 기반 강화

### 6.3 기존 데이터 호환

- 마이그레이션 008 — `subject` 컬럼 nullable
- 기존 entry 의 `subject = NULL` 그대로 작동 (UI 에 "미분류" 로 표시)
- **선택적 일괄 분류** 도구 (`bin/sowing reclassify`) — 카테고리 → subject 자동 매핑 제안 + 사용자 검토 후 적용

---

## 7. MVP 작업 분해 (Phase 15)

### Phase 15 — Subject 축 (W33~W34)

```
W33-T01  Domain — subject 필드 추가 (4 mode)
W33-T02  Migration 008 — entries.subject column + index
W33-T03  CreateMemo/Note/Record/Plan use case — subject 인자
W33-T04  UI — 빠른 메모 모달 subject chip 4개
W33-T05  UI — 필기·기록 작성 폼 subject 라디오
W34-T01  /view/recent 의 subject chip 필터
W34-T02  Subject × 연도 매트릭스 페이지
W34-T03  bin/sowing reclassify — 카테고리 → subject 자동 제안 도구
W34-T04  spec ~50 + 캡쳐 갱신
```

### Phase 16 — Archive (W35)

```
W35-T01  Migration — entries.archived_at + archive_reason
W35-T02  ArchiveEntry / UnarchiveEntry use case
W35-T03  ArchiveController + /archive 페이지
W35-T04  검색·합성기·view_recent 모두 archive 자동 제외
W35-T05  학생별·학년도별 일괄 archive UI
W35-T06  spec ~30
```

### Phase 17 — Export Templates (W36~W37)

```
W36-T01  Template 인프라 (10_Templates/exports/)
W36-T02  ExportController + /export 페이지
W36-T03  GenerateStudentRecord use case (생기부)
W36-T04  GenerateConsultation use case (상담부)
W37-T01  GenerateMeetingMinutes use case (회의록)
W37-T02  GenerateProjectProposal use case (사업계획서)
W37-T03  GenerateBudgetRequest use case (예산요구서)
W37-T04  PDF/DOCX export (Prawn + caracal 또는 wkhtmltopdf)
W37-T05  spec ~40
```

**누적**: ~120 spec + 3 마이그레이션 + 7 신규 use case + 2 신규 controller + 10+ view.
**예상 기간**: 3~4주 (단일 개발자 기준).

---

## 8. ADR 영향 + 신규 결정

### 영향 없음

- ADR-001 (마크다운 SoT): subject 는 frontmatter 추가
- ADR-009 (로컬-first): 모든 변경 로컬
- ADR-013 (자율 mutation 0): archive/export 모두 사용자 명시 클릭
- ADR-014 (동사 IA): subject 는 명사 mode 위에 얹는 축, IA 영향 0

### 신규 ADR 후보

**ADR-015: Subject 4축 제약 분류 도입**

> 비전 D 의 4축 (인물·교과·계획서·정체성) 을 entry 메타데이터로 명시 도입.
> 자유 카테고리 (소분류) 와 별도 — **상위 4 enum 제약**. nullable (기존 데이터 호환).
> 4축 합의로 30년 누적의 의미 단위 안정성 확보.

**ADR-016: Archive 메타데이터 (active vs archived 이분)**

> 30년 누적의 무거움 회피. 졸업·학년종료 등 사용자 명시 이관 시
> `archived_at` timestamp 기록. 일상 UX (검색·회상·합성기) 에서 자동 제외.
> 폴더 구조 변경 없음 — 메타만 (옵시디언 호환 유지).

**ADR-017: Template-based Export (생기부·상담부 등 공식 양식)**

> `10_Templates/exports/*.md.erb` 사용자 편집 가능 ERB 양식.
> 학교별·연도별 양식 차이 자체 흡수. PDF·DOCX 출력은 외부 도구 (Prawn 등).
> 자동 합성과의 차이: 양식 적용은 **사용자 명시 클릭**, LLM 옵션은 검토 대기 폴더.

---

## 9. 비전 vs MVP — 최종 매트릭스

| 비전 (A~E) | 현재 v0.1.8 | MVP 후 (v0.2.0 예상) |
|---|---|---|
| **A. 30년 누적·전달** | ✅ + ⚠ vault 공유 | ✅ + Export 양식 5종 |
| **B. 입력 4 mode** | ✅ 메모·필기·기록·계획 | ✅ + subject 메타 |
| **C. 처리 흐름 5단계** | ✅ 4단계 + ❌ 이관 | ✅ 5단계 (Archive 신설) |
| **D. 판단 기준 4축** | ⚠ 자유 카테고리만 | ✅ Subject 4축 명시 |
| **E. 출력 3축** | ⚠ 시간·주제만 | ✅ 시간·주제·**용도** 3축 |

### MVP 후 사용자 시나리오

```
1. 매일: ⌘⇧M → 메모 한 줄 (subject 자동 또는 chip 선택)
2. 평상시: /view/recent?subject=person → 최근 인물 관련
3. 이벤트시: 🌱 합성기 → 학생 디제스트 (학기말)
4. 학기말: /export/student-record/민준 → 생기부 1 페이지 PDF
5. 학년말: /export/meeting/2026-종업식 → 회의록 + Archive 일괄
6. 30년차: /archive?year=2010 → 옛 학생 보고서 재작성 자료
```

---

## 10. 다음 단계 (실행 권장)

### 즉시 (베타 인터뷰 전)

- 본 문서 (MVP_VISION.md) 사용자 confirm
- 4축 매핑 미세 조정 (수업회고 → curriculum? identity?)
- 5 template 우선순위 확정 (생기부·상담부 먼저, 예산은 나중)

### Phase 15 진입 (W33, 2026-05 후반 예상)

- W33-T01: Domain subject 필드 추가
- 사용자 명시 동의 후 시작

### 베타 인터뷰 (2026-08)

- v0.1.8 기준 Phase 13 검증
- MVP 진행 의향 의견 수렴
- 4축 명명 검증 ("정체성" 이 직관적인가)

### MVP 출시 목표 (v0.2.0, 2026-09~10 예상)

- Subject 4축 ✅
- Archive ✅
- Export 5종 ✅
- 누적 spec ~1900, 캡쳐 ~40

---

## 부록 — 관련 문서

- [README.md](../README.md)
- [docs/MANUAL.md](MANUAL.md) — v0.1.8 사용 매뉴얼
- [docs/USER_GUIDE.md](USER_GUIDE.md) — 입문 가이드
- [docs/REDESIGN_IA.md](REDESIGN_IA.md) — Phase 13 동사 IA 재설계
- [docs/DECISIONS.md](DECISIONS.md) — ADR 14건
- [docs/SPEC.md](SPEC.md) — 전체 기술 명세
- [ROADMAP.md](../ROADMAP.md) — Phase 1~14 작업 분해

---

**한 줄 요약**:

> 현재 Sowing v0.1.8 은 비전 A·B·C·E.1 을 충족. **D (4축 주제) + E.2 강화 + E.3 (용도별) + C 의 이관**
> 이 MVP 의 3 핵심 변화 (Subject·Archive·Export Templates).

🌱
