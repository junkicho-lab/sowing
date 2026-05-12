# Sowing 🌱 모듈형 재구조화 청사진 (Refactoring Blueprint)

> **작성일**: 2026-05-12
> **현재 버전**: v0.1.8 (1674 spec / 0 failures)
> **목표 버전**: v0.2.0 (비전 A~E 완성, 모듈형 아키텍처)
> **기간 추정**: 6~8주 (Phase 15~20)
> **작성 원칙**: 탑 프로그래머의 7 원칙 (§0 참조)

---

## 0. 작성 원칙 — 7 Practices of a Senior Engineer

**원칙 1. 측정 가능한 가역성** (Reversibility)
모든 단계는 `git revert` 한 번으로 되돌릴 수 있어야 한다. 단일 commit = 단일 책임.

**원칙 2. Strangler Fig** (Martin Fowler)
기존 코드를 한 번에 갈아엎지 않는다. 새 모듈을 옆에 짓고, 라우트를 점진 이전. 옛 코드는 마지막에 제거.

**원칙 3. Domain First, Persistence Last**
도메인 객체부터 정의. 마이그레이션·인덱싱은 도메인이 안정된 후. (DDD)

**원칙 4. Spec 우선** (Test-First for Refactoring)
변경 전: 회귀 spec 작성으로 현 동작 고정. 변경 후: spec 통과로 행위 보존 증명.

**원칙 5. Bounded Context** (Eric Evans)
4 모듈 (Capture·Knowledge·Insight·Output) 경계 명확. 모듈 간 의존은 **인터페이스**, 직접 클래스 참조 금지.

**원칙 6. 사용자 합의 게이트** (User Acceptance Gates)
큰 결정 (도메인 통합·삭제) 은 사용자 confirm 후 진행. Stage 시작 전 합의 게이트.

**원칙 7. 비결정 위험 회피** (Determinism)
같은 commit 으로 누가 빌드해도 같은 결과. 마이그레이션·자동 변환은 reversible + idempotent.

---

## 1. 비전 → 도메인 매핑 (DDD Bounded Context)

### 1.1 4 Bounded Context 정의

```
┌──────────────────────────────────────────────────────────┐
│ 1. Capture (포착)                                          │
│    - 매일 떠오르는 생각·메모·음성·관찰                       │
│    - 진입장벽 0, 분류 최소                                  │
│    - 도메인: CaptureItem (subject? subtype? body)          │
│                                                             │
│ 2. Knowledge (지식·기록)                                    │
│    - 정리된 노트·체계적 기록·계획                            │
│    - subject 4축 명시 + 카테고리                            │
│    - 도메인: Record (보존), Plan (미래), Reference (자료)   │
│                                                             │
│ 3. Insight (통찰·합성)                                      │
│    - 17 합성기 + 자기 거울                                  │
│    - 검토 대기 폴더 (자율 mutation 0)                       │
│    - 도메인: Synthesis (type/source/body/status)            │
│                                                             │
│ 4. Output (출력·전달)                                       │
│    - 생기부·상담부·회의록·사업계획서·예산요구서             │
│    - Template + Export (PDF·DOCX·MD)                       │
│    - 도메인: ExportTemplate, ExportJob                      │
└──────────────────────────────────────────────────────────┘
```

### 1.2 모듈 의존 그래프 (Acyclic)

```
              ┌──────────┐
              │  Output  │ (Template-based)
              └────┬─────┘
                   │  의존
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
   ┌─────────┐           ┌───────────┐
   │ Insight │ ◄──의존── │ Knowledge │
   └────┬────┘           └─────┬─────┘
        │                      │
        └──────────┬───────────┘
                   │  의존
                   ▼
              ┌─────────┐
              │ Capture │  (모두의 base)
              └─────────┘
```

**핵심 규칙**:
- `Capture` 는 어디에도 의존하지 않음 (base layer)
- `Output` 만 모든 컨텍스트 의존 (사용자 출력의 최종 모음)
- 같은 layer 간 직접 참조 금지 (양방향 의존 회피)

### 1.3 현재 도메인 → 새 컨텍스트 매핑

| 현재 (v0.1.8) | 새 컨텍스트 | 이전 방식 |
|---|---|---|
| `Memo` | `Capture::Item` (subtype: thought) | 1:1 rename |
| `Note` | `Knowledge::Reference` (자료·공부) 또는 `Capture::Item` (subtype: detail) | 분리 검토 |
| `Record` | `Knowledge::Record` | 1:1 rename + subject 추가 |
| `Plan` | `Knowledge::Plan` | 1:1 rename + subject 추가 |
| 합성기 17종 | `Insight::Synthesizer::*` | namespace 이전 |
| Template (10_Templates) | `Output::Template` | namespace + ERB export 추가 |

### 1.4 Note 의 정체성 — 합의 필요

**문제**: 현재 Note 는 "필기" 인데, 비전에선 "공부 자료" 와 "체계적 보고서" 가 별도 항목. Note 가 둘 다 흡수해야 하나?

**옵션 A**: Note 유지 → `Knowledge::Reference` (공부) + `Knowledge::Record` (보고) 분리
**옵션 B**: Note 폐기 → 모두 `Knowledge::Record` 로 흡수
**옵션 C**: Note 유지 → `Knowledge::Reference` 로 통일 (공부 자료 + 정리 노트 모두)

→ **Stage 0 합의 게이트 #1**: 사용자 선택 필요.

---

## 2. 모듈 구조 (디렉토리)

### 2.1 새 디렉토리 구조

```
lib/sowing/
├── core/                      ← 공통 인프라 (기존 infrastructure/)
│   ├── db/
│   ├── filesystem/
│   ├── markdown/
│   ├── audit_log.rb
│   └── settings.rb
│
├── capture/                   ← Bounded Context #1
│   ├── domain/
│   │   └── item.rb            (CaptureItem)
│   ├── repository/
│   │   └── capture_repo.rb
│   ├── use_case/
│   │   ├── create_item.rb
│   │   └── promote_to_knowledge.rb
│   ├── controller/
│   │   └── capture_controller.rb
│   └── public_api.rb          ← Module Façade (외부 의존 진입점)
│
├── knowledge/                 ← Bounded Context #2
│   ├── domain/
│   │   ├── record.rb
│   │   ├── plan.rb
│   │   └── reference.rb       (option A 시)
│   ├── repository/
│   │   ├── record_repo.rb
│   │   ├── plan_repo.rb
│   │   └── archive_repo.rb    ← NEW (Phase 16)
│   ├── use_case/
│   │   ├── create_record.rb
│   │   ├── create_plan.rb
│   │   ├── archive_entry.rb   ← NEW
│   │   └── unarchive_entry.rb
│   ├── controller/
│   │   ├── records_controller.rb
│   │   ├── plans_controller.rb
│   │   └── archive_controller.rb
│   └── public_api.rb
│
├── insight/                   ← Bounded Context #3
│   ├── domain/
│   │   └── synthesis.rb       (통합 도메인 — type/body/status)
│   ├── synthesizer/           (17 종)
│   │   ├── student_digest.rb
│   │   ├── self_mirror.rb
│   │   └── ... (15 more)
│   ├── repository/
│   │   └── synthesis_repo.rb
│   ├── controller/
│   │   └── insight_controller.rb (= 기존 SynthController)
│   └── public_api.rb
│
├── output/                    ← Bounded Context #4 (NEW)
│   ├── domain/
│   │   ├── export_template.rb
│   │   └── export_job.rb
│   ├── template/              (ERB 5종)
│   │   ├── student_record.erb
│   │   ├── consultation.erb
│   │   ├── meeting.erb
│   │   ├── project_proposal.erb
│   │   └── budget_request.erb
│   ├── use_case/
│   │   ├── generate_student_record.rb
│   │   ├── generate_consultation.rb
│   │   └── ...
│   ├── exporter/
│   │   ├── pdf_exporter.rb    (Prawn)
│   │   ├── docx_exporter.rb   (caracal)
│   │   └── markdown_exporter.rb
│   ├── controller/
│   │   └── export_controller.rb
│   └── public_api.rb
│
└── application.rb             ← Sinatra mount (기존 동일)
```

### 2.2 Module Façade 패턴 (`public_api.rb`)

각 모듈의 외부 인터페이스만 노출. 내부 구현은 캡슐화:

```ruby
# lib/sowing/capture/public_api.rb
module Sowing
  module Capture
    # 외부 모듈이 사용할 메서드만. 내부 클래스 직접 참조 X.
    def self.create_item(body:, subject: nil, subtype: nil, **opts)
      UseCase::CreateItem.new.call(body:, subject:, subtype:, **opts)
    end

    def self.find(id) = Repository::CaptureRepo.new.find(id)
    def self.recent(limit: 10) = Repository::CaptureRepo.new.recent(limit:)
  end
end
```

다른 모듈은:
```ruby
# Knowledge 가 Capture 의 item 을 promote 받을 때
item = Sowing::Capture.find(item_id)
# ↑ Capture::UseCase::CreateItem 같은 내부 클래스 직접 참조 X
```

### 2.3 의존성 룰 검증 (자동화)

`bin/sowing-arch-check` 신규 — 모듈 의존 그래프 위반 감지:

```sh
# 위반 예시 (knowledge 가 output 참조 — 역방향)
lib/sowing/knowledge/use_case/create_record.rb:42
  → require "sowing/output/exporter/pdf_exporter"
  ✗ 의존 위반: knowledge → output (output 만 knowledge 의존 가능)
```

ruby 의 `require_relative` + `Module.constants` 추적으로 구현. CI 에 통합.

---

## 3. 단계별 실행 절차 (Stage 0~5)

### Stage 0: 분석 + 합의 (1주)

**목표**: 사용자와 모듈 경계·도메인 매핑 합의. 코드 변경 0.

**작업**:
- [ ] **합의 게이트 #1**: Note 의 정체성 결정 (A/B/C 옵션)
- [ ] **합의 게이트 #2**: Subject 4축 명명 확정
  - `person` vs `people` vs `human`?
  - `plan_doc` 가 직관적인가? (Plan mode 와 헷갈림 — `proposal` 또는 `document` 검토)
  - `identity` vs `philosophy` vs `vision`?
- [ ] **합의 게이트 #3**: Export 5종 우선순위
  - 학기말 즉시 필요 → 생기부·상담부 P0
  - 학년말 필요 → 회의록·사업계획서 P1
  - 연 1회 → 예산요구서 P2
- [ ] **합의 게이트 #4**: 기존 mode 폐기 가능성
  - `Note` 폐기 vs 유지?
  - `Memo` 와 `Note` 의 통합 가능?
- [ ] **합의 게이트 #5**: 기간 추정 (6주 vs 8주)
- [ ] 본 문서 (REFACTORING_BLUEPRINT.md) 최종 confirm

**산출물**:
- 합의 결정 5건 → `docs/REFACTORING_DECISIONS.md` 신규
- ADR-015 ~ ADR-019 초안

**검증**:
- 사용자 명시 confirm (이메일·이슈 코멘트 또는 commit message)

**롤백**: N/A (코드 변경 0)

---

### Stage 1: 모듈 골격 + Façade (1주, Phase R1)

**목표**: 새 디렉토리 + `public_api.rb` 만 생성. 기존 코드는 그대로 작동. 새 모듈은 비어있되 import 가능.

**작업**:
1. R1-T01 `lib/sowing/core/` 디렉토리 + 기존 `infrastructure/` 의 file 이동 (rename)
2. R1-T02 `lib/sowing/capture/public_api.rb` (메서드 stub, internal::*)
3. R1-T03 `lib/sowing/knowledge/public_api.rb`
4. R1-T04 `lib/sowing/insight/public_api.rb`
5. R1-T05 `lib/sowing/output/public_api.rb` (빈 모듈)
6. R1-T06 Zeitwerk inflector 갱신 (`config/application.rb`)
7. R1-T07 `bin/sowing-arch-check` 신규 (의존성 룰 자동 검증)
8. R1-T08 spec: 각 public_api 호출 가능 + arch-check pass

**산출물**:
- 4 모듈 디렉토리 + 4 façade
- arch-check binary
- spec 1674 → ~1690 (+16 façade 호출 + arch-check)

**검증**:
- 기존 1674 spec 모두 통과 (행위 보존)
- arch-check 0 위반
- `bundle exec puma` 정상 부팅

**롤백**: `git revert` 8 commit 시리즈

---

### Stage 2: Capture 모듈 (1주, Phase R2)

**목표**: `Memo` → `Capture::Item` 이전. 기존 라우트 `/memos` 유지 (호환).

**작업**:
1. R2-T01 `Capture::Domain::Item` 신설 — `Memo` 의 모든 속성 + subject + subtype
2. R2-T02 `Capture::Repository::CaptureRepo` — 기존 `VaultRepo` 의 memo 부분 이전
3. R2-T03 `Capture::UseCase::CreateItem` — 기존 `CreateMemo` 이전 + subject 인자
4. R2-T04 `Capture::Controller::CaptureController` — `/memos` 마운트
5. R2-T05 기존 `Memo` 도메인을 `Capture::Item` 의 alias 로 (호환층)
6. R2-T06 마이그레이션 008: `entries.subject` column 추가 (Stage 5 까지 nullable)
7. R2-T07 spec — 기존 `spec/system/memos_*` 그대로 통과 + Capture 신규 spec ~20

**검증**:
- 기존 1690 spec 통과
- 신규 ~20 — Capture 모듈 단독 spec
- 운영 시나리오: ⌘⇧M → 메모 작성 → /memos 표시 100% 동작
- arch-check 통과

**롤백**: 마이그레이션 008 down + commit revert

**합의 게이트 #6**: 이 시점에 `Note` 의 정체성 재확인. Capture 만으로 충분한가?

---

### Stage 3: Knowledge 모듈 (1.5주, Phase R3)

**목표**: `Note`, `Record`, `Plan` 이전 + **Archive** + **Subject 4축 적용**.

**작업**:
1. R3-T01 `Knowledge::Domain::Record` 신설 + subject 필드
2. R3-T02 `Knowledge::Domain::Plan` 신설 + subject 필드
3. R3-T03 (옵션) `Knowledge::Domain::Reference` (Note 의 새 이름)
4. R3-T04 `Knowledge::Repository::*` (RecordRepo, PlanRepo, ReferenceRepo)
5. R3-T05 **`Knowledge::UseCase::ArchiveEntry`** + **`UnarchiveEntry`**
6. R3-T06 마이그레이션 009: `entries.archived_at` + `archive_reason`
7. R3-T07 `Knowledge::Controller::ArchiveController` + `/archive` 페이지
8. R3-T08 검색·합성기·view_recent 모두 `archived_at IS NULL` 필터 추가
9. R3-T09 일괄 archive UI (학생별·학년도별)
10. R3-T10 Subject × 연도 매트릭스 (기존 카테고리 × 연도 옆에)
11. R3-T11 reclassify 도구 (`bin/sowing reclassify`) — 카테고리 → subject 자동 제안
12. R3-T12 spec ~60 (Knowledge 모듈 전체)

**검증**:
- 1710 → ~1770 spec
- Archive 동작: 학생 archive → /view/recent 에서 즉시 사라짐
- Subject 필터: `/view/recent?subject=person` 정상
- 기존 사용자 시나리오 100% (subject = nil 인 entry 도 정상)

**합의 게이트 #7**: Subject 자동 분류 정확도 검토. reclassify 결과 5명 표본으로 검증.

---

### Stage 4: Insight + Output 모듈 (2주, Phase R4)

**목표**: 17 합성기 → `Insight::Synthesizer::*`. **Output 5 template** 신설.

**Phase R4a (Insight, 1주)**:
1. R4a-T01 `Insight::Domain::Synthesis` — 통합 도메인 (type/source/body/status)
2. R4a-T02 17 합성기 → `Insight::Synthesizer::*` namespace 이전 (logic 변경 0)
3. R4a-T03 `Insight::Repository::SynthesisRepo`
4. R4a-T04 `Insight::Controller::InsightController` (기존 SynthController)
5. R4a-T05 기존 합성기 spec 그대로 통과 (행위 보존)

**Phase R4b (Output, 1주)**:
6. R4b-T01 `Output::Domain::ExportTemplate` + `ExportJob`
7. R4b-T02 5 ERB template (`10_Templates/exports/`)
8. R4b-T03 5 use case: `GenerateStudentRecord`, `GenerateConsultation`, `GenerateMeetingMinutes`, `GenerateProjectProposal`, `GenerateBudgetRequest`
9. R4b-T04 `Output::Exporter::*` — Markdown·PDF (Prawn)·DOCX (caracal) 3종
10. R4b-T05 `Output::Controller::ExportController` + `/export` 페이지
11. R4b-T06 spec ~80

**검증**:
- ~1850 spec
- /export 진입 → 5 template 선택 → 학생 입력 → PDF 다운로드 정상
- 모든 17 합성기 그대로 작동
- arch-check 통과

**합의 게이트 #8**: 5 template 양식이 학교 실무와 맞는가? 1명 베타 테스터에게 PDF 검토.

---

### Stage 5: 폐기 + 검증 + 출시 (1주, Phase R5)

**목표**: 옛 코드 제거 + 최종 검증 + v0.2.0 출시.

**작업**:
1. R5-T01 합의된 폐기 모드 제거 (예: Note 폐기 시)
2. R5-T02 옛 namespace alias 제거 (`Memo` → `Capture::Item`)
3. R5-T03 `lib/sowing/{controllers,repositories,use_cases,domain,infrastructure}/` 폴더 — 모듈로 모두 이전됐는지 확인 + 제거
4. R5-T04 마이그레이션 008·009 의 nullable subject 를 NOT NULL 로 (선택 — 모든 데이터 마이그레이션 후)
5. R5-T05 `bin/sowing-doctor` 의 검사 항목 갱신
6. R5-T06 USER_GUIDE.md·MANUAL.md·MVP_VISION.md v0.2.0 갱신
7. R5-T07 CHANGELOG.md [0.2.0] 섹션
8. R5-T08 version.rb 0.1.x → 0.2.0
9. R5-T09 release-check 통과 (rspec·standardrb·5x stress·doctor·eval)
10. R5-T10 tag v0.2.0 + GitHub Release

**검증**:
- 전체 ~1850 spec / 0 failures
- 5x stress 안정
- arch-check 0 위반
- 사용자 시나리오 6종 manual 통과 (위 §1.4 의 1~6 시나리오)

**합의 게이트 #9**: v0.2.0 출시 직전 사용자 final confirm.

**롤백**: 출시 후 critical 버그 시 v0.1.8 로 1 명령 (`git tag rollback-v0.2.0` + revert merge).

---

## 4. 위험 관리 + 회복 전략

### 4.1 위험 매트릭스

| 위험 | 확률 | 영향 | 완화 |
|---|---|---|---|
| 마이그레이션 데이터 손실 | 🟡 Medium | 🔴 High | 008·009 down 마이그레이션 필수 + vault 백업 |
| Subject 자동 분류 오류 | 🔴 High | 🟡 Medium | reclassify 가 자동 적용 X — 사용자 검토 필수 |
| Note 폐기 후 옛 데이터 미손실 검증 | 🟡 Medium | 🔴 High | Stage 5 전 1주 dry-run + 베타 테스터 검증 |
| Strangler Fig 중간 단계 깨짐 | 🟡 Medium | 🟡 Medium | 각 stage 끝 release-check 통과 의무 |
| 합성기 17종 동시 이전 시 회귀 | 🔴 High | 🟡 Medium | R4a 의 단일 namespace 이전만 (logic 0 변경) |
| Export PDF 의 한국어 폰트 깨짐 | 🟡 Medium | 🟡 Medium | Prawn + Pretendard 폰트 사전 검증 |

### 4.2 단계별 회복

각 Stage 시작 전:
1. `git tag pre-stage-N` (롤백 anchor)
2. 마이그레이션 있다면 down 함수 검증 (`bundle exec rake db:rollback`)
3. vault 백업 (`tar czf vault-backup-$(date +%Y%m%d).tar.gz ~/Documents/SowingVault`)

Stage 실패 시:
```sh
git reset --hard pre-stage-N        # 코드 롤백
bundle exec rake db:rollback         # DB 롤백
tar xzf vault-backup-YYYYMMDD.tar.gz # vault 복구 (선택)
```

### 4.3 부분 출시 (Feature Flag)

Stage 3 (Archive·Subject) 가 큰 작업 — 위험 분산을 위해 feature flag:

```ruby
# Settings.refactoring_stage_3_enabled = true/false
if Sowing::Infrastructure::Settings.load["refactoring_stage_3_enabled"]
  # 신규 Subject UI 노출
else
  # 기존 카테고리 UI
end
```

- 베타 테스터 일부만 활성화
- 1주 검증 후 default ON
- 문제 시 즉시 OFF (코드 변경 0)

---

## 5. 자동화 + 검증

### 5.1 CI 단계마다 통과해야 할 게이트

```sh
# Stage N 끝, commit 전 자동:
bundle exec rspec --format progress           # 행위 보존
bundle exec standardrb                         # lint
bin/sowing-arch-check                          # 의존성 룰
bin/sowing-doctor                              # vault 정합성
bundle exec rake db:migrate && db:rollback    # 마이그레이션 가역
```

### 5.2 행위 보존 spec (Characterization Test)

리팩토링 전 현재 동작을 spec 으로 고정:

```ruby
# spec/refactoring/v018_baseline_spec.rb
# Stage 0 끝에 생성. Stage 5 까지 항상 통과해야 함.

RSpec.describe "v0.1.8 baseline 행위 보존" do
  it "⌘⇧M → 메모 작성 → /memos 표시" do
    # 단축키 → 모달 → 저장 → 목록 확인
    # 이 spec 이 Stage 1~5 동안 항상 통과해야 함
  end

  it "17 합성기 — 각 type 의 출력 형식 보존" do
    # 모든 합성기를 deterministic 모드로 실행 → 출력 byte-equal 검증
  end

  # ... 50+ characterization spec
end
```

### 5.3 모듈 spec (모듈 단독 검증)

각 모듈은 자체 spec 폴더:

```
spec/
├── capture/
│   ├── domain/item_spec.rb
│   ├── repository/capture_repo_spec.rb
│   └── use_case/create_item_spec.rb
├── knowledge/
├── insight/
└── output/
```

각 모듈 spec 은 **다른 모듈 의존 X** (mock 또는 in-memory fake 사용).

---

## 6. Commit 규칙 (단일 책임 + 가역성)

### 6.1 Commit message 형식

```
[R{stage}-T{task}] 한 줄 요약 ({Bounded Context})

본문:
- 무엇을 (what)
- 왜 (why)
- 어떻게 (how — 비결정 의사결정만)
- 가역 (rollback method)

검증:
- spec 카운트 변화
- arch-check 결과
- 수동 검증 (필요 시)

Co-Authored-By: ...
```

### 6.2 단일 책임 commit

1 commit = 1 의도. 예시:
- ❌ `[R2] Capture 전체 이전 + spec 갱신 + arch-check 추가` (3 의도)
- ✅ `[R2-T01] Capture::Domain::Item 신설 (Memo 의 1:1 이전, logic 0 변경)` (1 의도)
- ✅ `[R2-T07] Capture 모듈 spec 추가 (~20 case, 행위 보존)` (1 의도)

### 6.3 Commit 시리즈 예시 (Stage 2)

```
[R2-T01] Capture::Domain::Item 신설 (Memo 의 1:1 이전)
[R2-T02] Capture::Repository::CaptureRepo (VaultRepo memo 부분 이전)
[R2-T03] Capture::UseCase::CreateItem (CreateMemo 이전 + subject 인자)
[R2-T04] Capture::Controller mount + /memos 호환
[R2-T05] Memo → Capture::Item alias (Strangler Fig 호환층)
[R2-T06] Migration 008 — entries.subject column
[R2-T07] Capture 모듈 spec ~20 + 기존 memo spec 통과 확인
[R2-T08] arch-check 통과 확인 + commit 시리즈 완료
```

각 commit 은 단독으로 `bundle exec rspec` 통과해야 함 (atomic).

---

## 7. 사용자 합의 게이트 9개

본 청사진 진행 중 사용자 명시 confirm 필요 지점:

| # | 게이트 | 시기 | 결정 |
|---|---|---|---|
| **1** | Note 의 정체성 (A/B/C) | Stage 0 | A: 분리·B: 폐기·C: 통일 |
| **2** | Subject 4축 명명 | Stage 0 | enum 키 5건 확정 |
| **3** | Export 5종 우선순위 | Stage 0 | 생기부·상담부 먼저 |
| **4** | 기존 mode 폐기 가능성 | Stage 0 | Memo·Note 통합 여부 |
| **5** | 기간 추정 (6~8주) | Stage 0 | 본 청사진 confirm |
| **6** | Capture 완료 후 Note 재검토 | Stage 2 끝 | 합의 #1 유지·변경 |
| **7** | Subject 자동 분류 정확도 | Stage 3 중간 | reclassify 적용 여부 |
| **8** | Export 5종 양식 적합성 | Stage 4 끝 | 베타 테스터 1명 검증 |
| **9** | v0.2.0 출시 final | Stage 5 끝 | tag push 동의 |

### 합의 미합 시

- Stage 0 게이트 미합의 → 본 청사진 수정 후 재합의
- 중간 게이트 (#6~#8) 미합의 → Stage 정지 + 의사결정 회고
- #9 미합의 → v0.1.9 출시 + 부분 기능만 (Subject 4축 제외 등)

---

## 8. 일정 + 마일스톤

```
Week 33 (2026-05-19):  Stage 0 합의 + Stage 1 모듈 골격
Week 34 (2026-05-26):  Stage 2 Capture (Phase R2)
Week 35 (2026-06-02):  Stage 3 Knowledge 시작 (Archive·Subject)
Week 36 (2026-06-09):  Stage 3 계속 (subject 매트릭스·reclassify)
Week 37 (2026-06-16):  Stage 4a Insight (17 합성기 namespace)
Week 38 (2026-06-23):  Stage 4b Output (5 template 신설)
Week 39 (2026-06-30):  Stage 4b 계속 (PDF·DOCX)
Week 40 (2026-07-07):  Stage 5 폐기 + v0.2.0 출시
```

베타 인터뷰 (2026-08-12~16) 직전 v0.2.0 출시 → 베타 테스터는 v0.2.0 으로 인터뷰.

---

## 9. 비전 vs MVP vs Refactoring 차이

```
MVP_VISION.md (already):
  비전 → MVP 3 변화 (Subject·Archive·Export)
  Phase 15~17, ~3~4주

REFACTORING_BLUEPRINT.md (this):
  MVP 를 어떻게 구현할 것인가 — 모듈형 아키텍처로
  Phase R1~R5, ~6~8주

차이:
- MVP_VISION: WHAT (무엇을 만들까)
- REFACTORING_BLUEPRINT: HOW (어떻게 안전하게 만들까)
```

---

## 10. 본 청사진의 다음 단계

### 10.1 사용자 즉시 결정 필요

1. **본 청사진 confirm** (HOW 접근 동의)
2. **합의 게이트 9개 중 Stage 0 의 5개** (#1~#5) 답변

### 10.2 답변 받은 후 (Stage 0 작업)

- `docs/REFACTORING_DECISIONS.md` 신규 — 5 결정 기록
- ADR-015~ADR-019 초안
- `git tag pre-stage-1` (롤백 anchor)
- Stage 1 진입

### 10.3 Stage 1 첫 commit

```
[R1-T01] core/ 디렉토리 신설 + infrastructure/ 이전 (Phase R 진입)

지금까지의 lib/sowing/infrastructure/ 가 'Core 인프라' 역할만 했고
앞으로 4 Bounded Context 의 공통 base. 명시화 위해 core/ 로 rename.

변경:
- mv lib/sowing/infrastructure → lib/sowing/core
- require_relative paths 갱신
- Zeitwerk inflector "core" => "Core" 추가
- 모든 spec 통과 검증

가역: git revert + mv 역순
검증: 1674 spec 통과, arch-check 통과

Co-Authored-By: ...
```

---

## 부록 — 자주 묻는 질문

### Q1. 왜 6~8주? Phase 13 은 하루 만에 끝났는데?

Phase 13 은 14 commit 누적 — UI·합성기·문서. **도메인 객체 변경 0**.
본 청사진은 **도메인 자체 재구조화** — Memo → Capture::Item 같은 큰 이전.
spec 1674 개를 깨지 않고 옮기려면 단계적 + 검증 + 합의 필요.

### Q2. 일부만 진행 가능?

✅ 가능. 가장 가치 큰 단계:
- **Phase R3 (Archive·Subject)** 만 — 비전 D·C 직접 충족
- **Phase R4b (Export)** 만 — 비전 E.3 직접 충족
- Phase R1·R2·R4a 는 **순수 리팩토링** (사용자 가치 0, 기술 부채 청산)

베타 인터뷰 시간 압박 시 R3 + R4b 만 부분 진행.

### Q3. 옛 시스템 + 새 모듈 공존 기간?

Stage 1~4 동안 (5~6주). Stage 5 의 폐기 단계에서만 완전 이전.

### Q4. 실패 시?

각 Stage 끝 release-check 통과가 의무. 실패 시 그 Stage 전체 revert.
v0.1.8 은 항상 안정 출시 버전.

---

## 결론 — 한 줄

> 비전 A~E 를 안전하게 구현하기 위한 6~8주 모듈형 재구조화 청사진.
> **사용자 합의 9 게이트**, **Strangler Fig**, **Bounded Context 4 모듈**, **가역성 100%**.

🌱
