# 착수 가이드 (KICKOFF)

이 문서는 **본 프로젝트를 처음 받은 엔지니어 (또는 Claude Code) 가 첫 한 시간을 어떻게 써야 하는지** 안내합니다.

---

## 0. 본 패키지 안에 무엇이 있나

```
sowing/
├── README.md              # 공개 프로젝트 개요
├── KICKOFF.md             # ★ 본 파일 — 첫 한 시간 안내
├── CLAUDE.md              # ★ Claude Code 운영 매뉴얼
├── SETUP.md               # 개발 환경 설정 단계별
├── ROADMAP.md             # 8주 MVP 작업 분해 (작업 ID 부여됨)
├── docs/
│   ├── SPEC.md            # 전체 기술 명세서 (1100+ 줄)
│   └── DECISIONS.md       # 아키텍처 의사결정 기록 (ADR 10건)
├── Gemfile                # 의존성 (검증 완료)
├── Rakefile, config.ru
├── .ruby-version, .gitignore, .rspec, .standard.yml
├── bin/sowing             # CLI 진입점 (서브커맨드 골격)
├── bin/sowing-doctor      # 진단 도구
├── config/
│   ├── application.rb     # 앱 부트스트랩 + Sinatra 베이스
│   ├── routes.rb          # 라우트 (현재 / 와 /health 만)
│   └── locales/ko.yml     # 한국어 로케일 골격
├── lib/sowing/
│   ├── version.rb
│   └── infrastructure/
│       ├── paths.rb       # OS별 경로 결정 (구현 완료)
│       └── db.rb          # SQLite 연결 (구현 완료)
├── db/migrations/
│   └── 001_create_entries.rb  # entries 테이블 (적용 가능)
├── spec/
│   ├── spec_helper.rb     # RSpec 설정 (격리된 임시 볼트)
│   └── sowing_spec.rb     # 첫 샘플 테스트
├── templates/
│   └── lesson_reflection.md  # 1번째 교사 템플릿 (참조용)
└── packaging/             # (Week 8에 채워짐)
```

**구현 완료**: Paths, DB 연결, CLI 골격, 마이그레이션 1개, 첫 테스트
**미구현**: 도메인 객체, Use Case, Repository, Controller, View, 나머지 11개 템플릿

---

## 1. 첫 한 시간 체크리스트

### Step 1 — 문서 읽기 (15분)

다음 순서로 읽으세요. **순서가 중요합니다.**

1. **`README.md`** — 5분. 무엇을 만드는지 한 번에 파악.
2. **`docs/SPEC.md` §3 핵심 개념 모델** — 5분. 메모/필기/기록 3축. 다른 모든 결정의 뿌리.
3. **`docs/DECISIONS.md` ADR-001, 002, 003, 004, 005, 006** — 5분. 사용자가 확정한 핵심 결정.

이 3개만 먼저 읽으세요. 나머지는 작업하면서 필요할 때.

### Step 2 — 환경 구축 (20분)

`SETUP.md` 1~5번 따라하기:
1. Ruby 3.3.0 설치
2. `bundle install`
3. `bundle exec rake db:setup`
4. `bin/sowing dev`
5. 브라우저에서 `http://127.0.0.1:48723` 확인 ("Hello, Sowing 🌱" 표시)

`bundle exec rspec` 실행해서 샘플 테스트가 통과하는지 확인.

### Step 3 — 첫 작업 선택 (10분)

`ROADMAP.md` 의 **W1-T01** 부터 순서대로.

실제로 W1-T01은 본 패키지에서 이미 일부 구현되어 있습니다 (Gemfile, Rakefile, config 등). 검증·보완이 첫 작업입니다:

```bash
claude "ROADMAP.md의 W1-T01을 검증해줘. 이미 만들어진 부분을 확인하고 누락된 게 있으면 채워줘. 마지막으로 bin/sowing dev 가 동작하고 bundle exec rspec 가 통과하는지 확인해."
```

### Step 4 — Claude Code 첫 호출 (15분)

W1-T04 부터는 새로 만드는 작업입니다. 다음과 같이 호출하세요:

```bash
claude "W1-T04 작업을 진행해줘. CLAUDE.md의 도메인 객체 작성 패턴을 따르고, 작업 끝나면 spec 통과 결과를 보여줘."
```

Claude Code는 자동으로 `CLAUDE.md` 와 `ROADMAP.md` 를 참조합니다.

---

## 2. 첫 주에 만들 것 (Week 1 마일스톤)

```
✅ CLI에서 메모를 만들고, 옵시디언으로 열어볼 수 있다.
```

이게 끝나면 본 프로젝트의 핵심 가치 명제(옵시디언 호환 마크다운 자동 생성) 가 검증됩니다.

작업 순서:
1. W1-T01 ~ T03 (이미 일부 완료): 환경·DB·로깅
2. W1-T04: Ulid, TagSet (1~2시간)
3. W1-T05: Memo, Note, Record 도메인 객체 (반나절)
4. W1-T06: VaultRepo (반나절 — 가장 까다로움)
5. W1-T07: IndexRepo (반나절)
6. W1-T08: CreateMemo Use Case + CLI (1~2시간)

검증 시나리오:
```bash
bin/sowing memo "오늘 1교시 수업이 활기찼다"
ls $SOWING_VAULT/00_Inbox/
cat $SOWING_VAULT/00_Inbox/2026-*.md
# → frontmatter + 본문이 있어야 함

# 옵시디언으로 $SOWING_VAULT 를 열어 동일 파일 확인
```

---

## 3. Claude Code 활용 팁

### 한 작업씩 명확히 지시

❌ 좋지 않은 지시: "메모 기능 만들어줘"
✅ 좋은 지시: "ROADMAP.md의 W1-T08 작업을 진행해줘. 검증 항목까지 모두 통과하면 PR 메시지 초안을 한국어로 만들어줘"

### 자주 하는 작업

```bash
# 작업 진행
claude "W2-T05 진행"

# 작업 후 검증
claude "방금 만든 NotesController의 spec을 보강해줘"

# 옵시디언 호환성 점검
claude "방금 변경한 코드가 옵시디언 호환성을 깨지 않는지 확인하고 spec/compatibility 에 케이스를 추가해줘"

# 새 ADR 추가
claude "Sequel ORM 마이그레이션 컨벤션에 대한 ADR을 docs/DECISIONS.md 에 추가해줘. ADR-011 번호 사용"

# 진행 상황 업데이트
claude "ROADMAP.md 에서 W1 작업들을 완료 표시로 갱신해줘"
```

### 위험한 작업은 dry-run 먼저

```bash
claude "vault:reindex 작업을 만드는데, 먼저 dry-run 모드를 만들고 그게 검증되면 실제 모드를 추가해줘"
```

---

## 4. 의사결정이 필요할 때

다음 상황에서는 **사용자에게 먼저 확인**하세요 (Claude Code도 마찬가지):

- 기술 스택 변경 (Sequel → ActiveRecord, Sinatra → Rails 등)
- 외부 네트워크 호출 추가
- 사용자 데이터 형식 변경
- 의존성 gem 추가
- ROADMAP.md 의 작업 범위·순서 변경
- ADR 작성

확인 후 결정사항은 `docs/DECISIONS.md` 에 ADR로 추가합니다.

---

## 5. 일일 작업 종료 체크리스트

매일 작업을 마치기 전:

- [ ] `bundle exec rspec` 전체 통과
- [ ] `bundle exec standardrb` 통과
- [ ] `ROADMAP.md` 의 작업 상태 갱신
- [ ] 본일 변경된 파일 commit (작업 ID prefix: `[W2-T05] ...`)
- [ ] 새로 발견한 작업이나 결정이 있다면 문서에 반영

---

## 6. 막혔을 때

- **명세 모호**: `docs/SPEC.md` 검색 → 없으면 사용자 확인
- **기술 결정 필요**: `docs/DECISIONS.md` 검색 → 없으면 ADR 작성 후 사용자 확인
- **스택 사용법 모름**: 외부 문서 참조 (`docs/SPEC.md` §17.2 참고 자료)
- **어디서 시작할지 모름**: 본 문서 §2 다시 읽기

---

## 7. 본 프로젝트의 영혼

기능을 빠르게 쌓는 것보다 **본 프로젝트의 핵심 가치 두 가지**를 지키는 것이 중요합니다:

1. **옵시디언 호환성**: 이게 깨지는 순간 본 프로젝트의 존재 이유가 사라집니다.
2. **사용자 데이터 안전**: 한 번이라도 데이터를 잃게 만들면 신뢰가 무너집니다.

기능 1개 늦게 만드는 것보다, 데이터 1건 잃지 않는 것이 100배 중요합니다.

---

행운을 빕니다 🌱

— 2026-05-07

---

# Phase 2 진입자 안내 (W9~ 시작 시 읽기)

> 본 섹션은 Phase 1 (W1~W8 MVP) 완성 후 Phase 2 (Software 3.0 전환) 부터 합류하는
> 기여자 / Claude Code 세션 / 운영자를 위한 추가 가이드입니다. 위의 §1~§7 은
> Phase 1 시점 안내였고, 본 섹션은 **현재(2026-05-09 이후)** 의 상황입니다.

## P2.1 현재 상태 (2026-05-10 기준)

- **Phase 1 완료**: W1~W7 모두 ✅ + W8 부분 (T02 스캐폴드 + T06 doctor + T08 문서).
- **Phase 9 (Agent-Native Surface) ✅ 완료** (2026-05-09):
  - 12개 MCP 도구 (sensor 4 + actuator 4 + analytics 4) — `bin/sowing-mcp` stdio 진입점
  - 구조화 audit log (`vault/.sowing/audit.log`) — actor=user/agent/filesystem 구분
  - `docs/AGENT_GUIDE.md` (5분 셋업 + 12 도구 + 5 프롬프트 + 4 클라이언트)
- **Phase 10 (Eval Infrastructure) ✅ 완료** (2026-05-10):
  - 한국어 교사 글 corpus 100건 (`eval/corpus/teacher_writings/`, 6 task type)
  - `Sowing::Eval::Judge` + `Kappa` + 4 백엔드 (Fake/OpenAI/Anthropic/Ollama, Net::HTTP only)
  - 5 한국어 도메인 차원 (`Sowing::Eval::KoreanDimensions`)
  - `rake eval:run` + `.github/workflows/eval.yml` (회귀 자동 측정)
- **Phase 11 (Tier-1 LLM 합성) ✅ 완료** (2026-05-10):
  - W17-T01 `ExtractEntities` + migration 006 (`entities` UNIQUE(type,name) + `entity_mentions`) — 결정적 whitelist 30 인명 + 조사 패턴 + 과목·장소 사전, LLM 옵트인 NER
  - W17-T02 `SynthesizeStudentDigest` — 학생당 1 디제스트 (timeline + 인용 결정적 모드 + LLM 변화·패턴 분석 모드), `vault/.sowing/synth/students/` 에 `is_synth: true` frontmatter 로 저장, LLM 실패 시 결정적 fallback
  - W17-T03 `DetectStudentGaps` + Settings `class_roster` + Dashboard `gap-card` — 4주 미언급 학생 알림 (결정적·LLM 0)
  - W17-T04 `SynthController` + `/synth` 검토 UI — 수락 → `Domain::Record` + `Persistence#persist!` (audit `:create` + `:synth_accept`) → `30_Records/{YYYY}/학생기록/`. 거절 → `.sowing/trash` + audit `:synth_reject`. 명시적 사용자 클릭만 mutation
  - `AuditLog::ALLOWED_ACTIONS` — `:synth_generate`/`:synth_accept`/`:synth_reject` 추가 (Phase 12 fine-tuning preference 데이터)
  - 합성기 패턴 확립: `with_actor("agent")` 블록 + 결정적 fallback + frontmatter `is_synth: true` + `.sowing/synth/` 격리 (watcher 인덱싱 회피, 사용자 글과 명확 구분)
- **1095건 spec pass / standardrb clean / 5x stress 안정** (855 → 1095, +240 from Phase 9·10·11).
- **14개 컨트롤러 / 91개 라우트 / 3-tier 도메인 (Memo/Note/Record) + 합성 격리 (.sowing/synth) / 양방향 동기화 / 12종 템플릿 + 12건 샘플 / 4단계 온보딩 + 3분 튜토리얼 / 12 MCP 도구 / 100 eval corpus / 12 평가 차원 / Phase 11 합성기 3종 + entities/entity_mentions 테이블 + /synth 검토 UI**.
- **W8 deferred**: T01 시스템 트레이 / T03 macOS 코드사인 / T04 Windows 인스톨러 / T05 Linux AppImage / T07 베타 테스터.

## P2.2 가장 먼저 읽을 것 (순서 중요)

1. [`sowing-docs/background.md`](sowing-docs/background.md) — Karpathy의 Sequoia Ascent 2026 발표 요약. Phase 2 의 사상적 출발점.
2. [`sowing-docs/EVALUATION.md`](sowing-docs/EVALUATION.md) — 12 명제로 점검한 Sowing 평가 + Phase 9~12 로드맵 + 명시적 거부 5종.
3. [`docs/DECISIONS.md`](docs/DECISIONS.md) ADR-013 — Phase 2 전략 결정 + 거부 항목.
4. [`ROADMAP.md`](ROADMAP.md) "Phase 2: Software 3.0 전환" 섹션 — 작업 분해 (W9~W24).
5. [`CHANGELOG.md`](CHANGELOG.md) `[Unreleased]` — 직전 작업 누적.

이 5개를 30분 이내에 정독. 그 후에 코드 손대기 시작.

## P2.3 Phase 2 의 변하지 않는 원칙 (ADR-013)

다음 5종은 **절대 거부**:
1. ❌ 챗봇 UI — Sowing 안에 ChatGPT 클론 안 만듦
2. ❌ 자동 글쓰기 — LLM이 사용자 대신 글 안 씀 (합성·요약·연결만)
3. ❌ 클라우드 LLM 강제 — 옵트인. Ollama 등 로컬 LLM 동등 지원
4. ❌ "AI가 ~ 생각합니다" 의인화 카피
5. ❌ 자율 에이전트의 vault 변경 — 사용자 명시 수락 + audit log 의무

다음 5종은 **불변 원칙** (Phase 1에서 계승):
1. ✅ 마크다운 SoT — 옵시디언 호환성
2. ✅ 결정적 도메인 — 같은 입력 같은 출력
3. ✅ 검증 가능성 — spec·doctor·ConsistencyCheck
4. ✅ 로컬 우선 — 외부 서버 강제 안 함
5. ✅ 영구 삭제 금지 — 휴지통·충돌 백업

## P2.4 Phase 12 첫 작업 (W21-T01 SemesterReflection) 시작 절차

> **Phase 9·10·11 모두 완료**. Phase 12 (Tier-2 LLM 합성, W21~24) 진입 가능.
> Phase 11 의 합성기 패턴(`with_actor("agent")` + 결정적 fallback + `is_synth`
> frontmatter + `.sowing/synth/` 격리 + `/synth` 검토 UI 의 수락/거절 audit) 을
> 그대로 확장. 학생 1명 단위(Phase 11) → 학기 단위(Phase 12) 로 합성 범위 확대.

1. **상태 확인**:
   ```sh
   cd /Users/woodncarpenter/projects/sowing
   bundle exec rspec | tail -3         # 1095 examples, 0 failures 확인
   bundle exec standardrb | tail -2    # exit=0 확인
   bin/sowing-doctor | tail -25        # MCP / Audit / Eval / Phase 11 섹션 정상
   bundle exec rake eval:run           # FakeBackend baseline 회귀 확인 (선택)
   ```

2. **읽기 (필수, 순서대로)**:
   - `sowing-docs/EVALUATION.md` §3 Phase 12 작업 분해 (회고·패턴·모순 합성)
   - `lib/sowing/use_cases/synthesize_student_digest.rb` — Phase 11 합성기 패턴 참고 (frontmatter, deterministic fallback, LLM prompt 분리)
   - `lib/sowing/controllers/synth_controller.rb` — `/synth` UI 가 학생 디제스트와 학기 회고를 어떻게 동시에 다룰지 (synth_target prefix `student:` vs `semester:` 등)
   - `eval/corpus/teacher_writings/` — `task_type: reflection` / `contradiction` case 들 (Phase 12 검증 기반)

3. **W21-T01 작업** (SemesterReflection 합성기):
   - 새 use case: `Sowing::UseCases::SynthesizeSemesterReflection`
     - 입력: 100~500건 entries (3~6 개월 범위)
     - 출력: 마크다운 회고 (자주 등장한 학생 / 자주 다룬 주제 / 변화의 순간들 / 잘된 / 아쉬웠던 / 다음 학기 준비)
     - 청크 분할 + 점진적 합성 (long-context 한계 우회)
   - 저장: `vault/.sowing/synth/reflections/{semester_label}.md`
     - frontmatter: `is_synth: true`, `synth_target: "semester:2026-1"`, `synth_at`, `synth_source_count`, `synth_model`
   - `SynthController` 확장 — `/synth/reflections/:slug` 라우트 추가 (또는 통합 목록)
   - audit `:synth_generate`/`:synth_accept`/`:synth_reject` 그대로 재사용

4. **검증**:
   - eval 코퍼스 reflection task case 에서 coverage·structure·korean_consistency ≥ 4점 평균
   - 청크 분할 결정성 (같은 입력 → 같은 청크 경계) spec 화
   - `bundle exec rspec` — 회귀 1095건 + 신규 spec 통과
   - `bundle exec rake eval:run` — 차원 평균 하락 없음 (regressed=false)
   - lint clean. 5x stress 안정.

5. **커밋**: `[W21-T01] SemesterReflection 합성기 — 학기 회고 자동 합성 (청크 분할)`

이후 W21-T02 (LessonPattern 추출), W21-T03 (ContradictionDetector), W21-T04 (eval 종합 회귀) 진입.

## P2.5 Phase 2 작업 시 추가 검증 게이트

Phase 1 의 게이트(spec / lint / 5x stress) 에 다음 추가:

- **새 LLM 기능마다 eval 통과** (Phase 10 완성 후) — `bundle exec rake eval:run` 카파 ≥ 0.8
- **agent-facing API 변경 시 OpenAPI 스펙 갱신** — `docs/AGENT_GUIDE.md` 와 동기화
- **mutation use case 추가 시 audit log 통합** — 누락 시 spec fail 하도록 contract 검증

## P2.6 막힐 때

- **MCP 표준 모름**: [modelcontextprotocol.io](https://modelcontextprotocol.io) 공식 문서. Anthropic SDK 또는 Ruby 직접 구현 가능.
- **LLM 출력 평가 어떻게**: Phase 10 의 `lib/sowing/eval/judge.rb` 참고. 시작 전이라면 EVALUATION §3 Phase 10 작업 분해부터.
- **Phase 1 의 이상한 결정**: ADR-001~013 모두 사유 적혀 있음. 그래도 모르면 ADR 작성 후 사용자 확인.

## P2.7 Phase 2 의 영혼

Phase 1 은 "옵시디언 호환성 + 데이터 안전"이 영혼이었습니다. **Phase 2 는 한 가지가 추가됩니다**:

> *"You can outsource your thinking, but you can't outsource your understanding."*
> — Andrej Karpathy, Sequoia Ascent 2026

LLM 기능은 사용자의 **사고를 대신 해주는 게 아니라**, 손으로는 합칠 수 없었던
정보를 합쳐 사용자의 *이해를 향상* 시키는 도구입니다. 학생 디제스트는 교사가 절대
손으로 못 만드는 합성. 그러나 그것을 *해석하고 행동* 하는 것은 여전히 교사의 일.

이 경계를 지키지 못하면 Phase 2는 실패합니다.

— 2026-05-09 (Phase 2 kickoff)
