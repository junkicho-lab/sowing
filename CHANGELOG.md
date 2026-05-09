# Changelog

All notable changes to Sowing 🌱 will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase 10 (Eval Infrastructure) 진행 중
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

## [0.1.0] - MVP (W1~W6 핵심 기능)

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
