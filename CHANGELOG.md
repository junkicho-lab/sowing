# Changelog

All notable changes to Sowing 🌱 will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase 9 (Agent-Native Surface) 진행 중
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
