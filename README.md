# Sowing 🌱

> 옵시디언을 배우려고 앱을 켜는 것이 아니라,
> 앱을 매일 쓰다 보면 옵시디언을 쓰고 있게 됩니다.

**Sowing**은 옵시디언 사전 지식이 없는 교사가 매일 기록하는 습관을 들이도록 돕는 로컬 우선(local-first) 데스크톱 앱입니다.

## 핵심 컨셉

- **메모 → 필기 → 기록**의 3단계 인지 모델로 부담 없이 시작해서 깊이 있는 자산으로 키워나갑니다.
- 사용자가 작성한 모든 데이터는 **표준 마크다운 + YAML frontmatter** 로 저장됩니다.
- **본 앱이 사라져도 옵시디언으로 그대로 열어볼 수 있습니다.**
- 외부 서버에 데이터를 보내지 않습니다. 모두 로컬에 머뭅니다.

## 누구를 위한 앱인가

- 매일의 수업·학생·생각을 기록하고 싶은 현직 교사
- 노션·에버노트가 무겁게 느껴지는 분
- 옵시디언이 좋아 보이지만 어디서 시작할지 모르는 분
- 자신의 30년 경력을 정리·전수하고 싶은 중견 교사

## 기술 스택

- Ruby 4.0+ + Sinatra 4 (Modular)
- SQLite 3.34+ (FTS5 trigram 인덱스), 로컬 마크다운 파일 (콘텐츠)
- Hotwire (Turbo + Stimulus, importmap — 빌드 도구 0)
- CodeMirror 6 (마크다운 에디터)
- Listen gem (파일시스템 감시)
- Tebako 단일 실행파일 패키징 (스캐폴드 완료, 빌드 환경 준비 중)

## 시작하기

### 사용자 (출시 후)

[Releases 페이지](https://github.com/junkicho-lab/sowing/releases) 가 준비되면 OS별 인스톨러를 다운로드하세요.
현재는 소스 빌드만 가능합니다 — [SETUP.md](SETUP.md) 참조.

### 개발자

[`SETUP.md`](SETUP.md) 를 참조하세요.

## 구현 현황 — Phase 1 (W1~W8 MVP) 완료, Phase 2 (W9~W24) 진입 준비

> **Phase 1 (8주 MVP)**: 코드·문서 deliverable 모두 갖춰졌습니다 (855 spec pass).
> 실제 OS별 인스톨러 출시(W8-T03·T04·T05) 와 베타 테스터 모집(W8-T07)은
> Apple Developer 계정·Windows VM·실제 사용자가 필요해 후속 작업으로 분리.
> [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) · [docs/RELEASE.md](docs/RELEASE.md) 참조.
>
> **Phase 2 (W9~W24, 16주)**: [`sowing-docs/EVALUATION.md`](sowing-docs/EVALUATION.md) 의
> Karpathy 12 명제 점검 결과에 따라 Software 3.0 전환에 헌정. MCP 서버(W9~12) →
> Eval 인프라(W13~16) → Tier-1 LLM 합성(W17~20) → Tier-2 합성(W21~24).
> 결정은 [`docs/DECISIONS.md` ADR-013](docs/DECISIONS.md), 진입은
> [`KICKOFF.md` Phase 2 섹션](KICKOFF.md) 부터.

### ✅ 동작하는 기능

- **웹 UI** (`bin/sowing dev` → `http://127.0.0.1:48723`)
  - 한국어 대시보드: 최근 메모 5건 + 빈 상태 안내
  - 빠른 메모 모달: `Cmd/Ctrl+Shift+M` 호출, `Cmd/Ctrl+Enter` 저장, Turbo Stream으로 즉시 반영
  - 메모 목록 (`/memos`): 페이지네이션 30건/page, 100건 < 200ms
  - 필기 CRUD (`/notes`): 카테고리 4종(수업/연수/도서/회의) + 출처 필수 + 편집 시 path 이동(휴지통 보존)
  - 기록 CRUD (`/records`): 자유 카테고리 + datalist + `30_Records/{YYYY}/{category}/` + promoted_from
  - 태그 시스템 (`/tags`): frontmatter ∪ 본문 `#태그` 자동 인덱싱 + 태그 클라우드 + 태그별 entries
  - **승격 흐름**: 메모 → 필기 (`/memos/:id/promote_to_note`) / 메모 → 기록 / 필기 → 기록 — ULID 유지, promoted_from 자동, 옛 파일 휴지통
  - 마크다운 에디터: CodeMirror 6 (line wrapping, syntax highlight, basicSetup)
  - 라이브 프리뷰: 좌-우 split, Turbo Stream + 300ms 디바운스, 서버 응답 ~2ms
  - **자동완성**: `[[` 위키링크 + `#` 태그 (CodeMirror, 200ms 디바운스)
  - **위키링크 그래프**: 인덱스 자동 동기화 (outbound + inbound + broken 추적), title 매칭 시 자동 re-link
  - **검색** (`/search`): FTS5 trigram + 한국어 LIKE 폴백 (자동 라우팅), 모드/카테고리/태그/날짜 범위 AND 결합, 5,000건 < 500ms
  - **빠른 검색 모달**: `Cmd/Ctrl+K` 글로벌 단축키, 200ms 디바운스, ↑↓/Enter/Esc, 결과 클릭 시 navigate
  - **양방향 동기화**: Listen gem watcher + self-write 필터, 외부 편집 자동 인덱싱(ReindexEntry), frontmatter 없는 외부 파일 자동 입양(AdoptOrphan), 부팅 시 볼트↔인덱스 일관성 검증(ConsistencyCheck — 인덱스 wipe 후 자동 재구축)
  - **충돌 처리**: 폼 로드 시 disk hash 캡처(낙관적 잠금), PATCH 시 mismatch면 409 + Keep Mine(외부본 `.sowing/conflicts/` 백업) / Keep Theirs / 취소
  - **대시보드 통계**: 오늘/주(7일)/월 카운트, 모드별 분해(💭/📝/📖), 🔥 연속 작성일(streak — 오늘 비면 0), 진입마다 자동 재집계
  - **씨앗-숲 시각화**: 누적 entry 수에 따라 5단계(빈 흙→씨앗→새싹→나무→숲), 인라인 SVG(외부 라이브러리 0), 다음 단계까지 native progress bar
  - **템플릿 시스템** (`/templates`): vault 기반 마크다운 SoT, 시스템 12종 + 사용자 정의 override, 단순 `{{key}}` 치환 (date/time/date_korean/year/month/day 자동 채움)
  - **첫 실행 마법사** (`/onboarding`): 4단계 (welcome → vault → profile → samples) 후 자동 완료 마킹, 미완료 시 자동 redirect
  - **샘플 콘텐츠** (12건, `templates/samples/`): 메모 4 + 필기 4 + 기록 4 — 협동학습 한 주 스토리, 위키링크 그래프 시연용. `bundle exec rake vault:seed` 또는 온보딩에서 동의
  - **인터랙티브 튜토리얼** (`/tutorial`): 3분 4단계 가이드 (메모 → 필기 승격 → 기록 승격 → 완료), IndexRepo 카운트로 자동 진행 감지
  - **동기화 가이드** (`/guides`): iCloud / OneDrive / Dropbox / Syncthing — OS 매트릭스 + 설정 명령
  - **설정** (`/settings`): 프로필·데이터 위치·단축키 표시·백업/동기화 진입점·샘플 일괄 삭제(휴지통)·온보딩/튜토리얼 재실행
- **CLI**: `bin/sowing memo "내용"`, `bin/sowing-doctor`, `rake vault:seed`, `rake vault:reindex`
- **테스트**: `bundle exec rspec` (855건 통과)

### 구현된 컴포넌트

#### Domain (외부 의존 0)
| 모듈 | 설명 |
|------|------|
| `Domain::ValueObjects::{Ulid, TagSet}` | 불변 Value Object, frozen, 한국어 정렬 |
| `Domain::ValueObjects::GrowthStage` | 누적 entry 수 → 5단계(empty/seed/sprout/tree/forest) + 진행률 |
| `Domain::{Memo, Note, Record}` + `Entry` mixin | 3종 도메인, `to_frontmatter`/`to_markdown` |

#### Infrastructure
| 모듈 | 설명 |
|------|------|
| `Settings` | data_dir/settings.json — onboarding/tutorial 진행 상태, user_name 등 사용자 환경 영속화 |
| `Filesystem::SafeWriter` | 원자적 쓰기 (tempfile + rename), NFC 정규화, chaos test 통과 + self-write 등록 |
| `Filesystem::SelfWriteRegistry` | TTL 2초 thread-safe 레지스트리 (macOS realpath + NFC 정규화) — watcher 자체 쓰기 무시 |
| `Filesystem::FileWatcher` | Listen gem 래퍼 — `.md` only, `.sowing/` ignore, 500ms latency, force_polling 옵션 |
| `Markdown::{Parser, Serializer, ParsedDocument}` | front_matter_parser 래핑, round-trip 검증 |
| `Markdown::WikiLink` | `[[target]]` / `[[target\|alias]]` 추출·렌더 (옵시디언 호환) |
| `Markdown::Hashtag` | 본문 `#태그` 추출 (Crockford 호환 + digit-only 거부) |
| `Paths`, `DB` | OS별 경로, Sequel + SQLite 연결 (PRAGMA WAL/foreign_keys) |

#### Repository (단방향 의존 — Domain → Repo → Infra)
| 모듈 | 설명 |
|------|------|
| `Repositories::VaultRepo` | `write/read/list/delete(→trash)/update(path 이동)/file_hash/backup_conflict` |
| `Repositories::IndexRepo` + `IndexedEntry` | CRUD + tags 정규화 + category·date 검색 + paging + distinct categories + 위키링크 그래프 (outbound·inbound·broken·자동 re-link) + tag_cloud + complete/complete_tags + `search_with_filters` (FTS5↔LIKE 자동 라우팅, 한글 비율 ≥ 30% → LIKE) + `find_by_path`/`all_paths` |
| `Repositories::StatsRepo` | daily_stats 조회 — today/this_week/this_month + current_streak + total_all_time |
| `Repositories::TemplateRepo` | system(`templates/`) ∪ user(`vault/templates/`) 두 계층 + `{{key}}` 치환 (default_context: date/time/date_korean/year/month/day) |
| `Repositories::IndexRepo#find_samples` | ULID prefix `01KR1SAMP` 로 시드된 샘플 entry만 조회 (W7-T06 일괄 삭제) |

#### Use Case (Dry::Monads Result)
| 모듈 | 설명 |
|------|------|
| `UseCases::Persistence` | 공통 mixin: `persist!` / `repersist!` / `update_index!` |
| `UseCases::{Create,Update}{Memo,Note,Record}` | 5개 CRUD Use Case (Memo는 Update 미구현) — Update*는 `expected_file_hash`로 낙관적 잠금 + `force` 시 `.sowing/conflicts/` 백업 |
| `UseCases::{PromoteToNote, PromoteToRecord}` | 메모/필기 승격 — ID 유지, path 이동, promoted_from 자동 |
| `UseCases::ReindexEntry` | 외부 변경(:added/:modified/:removed) → 인덱스 동기화, mtime+hash 비교로 unchanged 단축 |
| `UseCases::AdoptOrphan` | frontmatter 없는 외부 파일 → path 기반 mode 추론 + ULID 부여 + in-place frontmatter 기록 |
| `UseCases::AggregateDailyStats` | entries → daily_stats 트랜잭션 재계산 (멱등, KST 고정) |
| `UseCases::SeedSamples` | `templates/samples/*.md` 12개 → vault, ULID 중복 자동 skip |
| `UseCases::DeleteSamples` | ULID prefix `01KR1SAMP` 매칭 entry 휴지통 이동 (사용자 entry 보존) |
| `Sync::Coordinator` | watcher → ReindexEntry → AdoptOrphan 폴백 파이프라인 + subscribe broadcast hook |
| `Sync::ConsistencyCheck` | 부팅 시 볼트 ↔ 인덱스 비교 → handle_event 합성 (wipe 후 재구축 검증됨) |

#### Web (Sinatra modular)
| 모듈 | 라우트 |
|------|------|
| `Controllers::ApplicationController` | base — views/public/helpers (markdown, escape, 한국어 날짜) |
| `Controllers::DashboardController` | `GET /` |
| `Controllers::MemosController` | `GET/POST /memos`, `POST` Turbo Stream + 승격 라우트 (`promote_to_note`/`promote_to_record`) |
| `Controllers::NotesController` | 6 actions + `promote_to_record` |
| `Controllers::RecordsController` | 6 actions |
| `Controllers::TagsController` | `GET /tags`, `GET /tags/:name` |
| `Controllers::SearchController` | `GET /search` — q/mode/category/tag/from/to/page (AND 결합) |
| `Controllers::TemplatesController` | `GET /templates`(목록), `GET /templates/new`, `POST /templates`, `GET /templates/:slug`(미리보기) |
| `Controllers::OnboardingController` | `/onboarding/*` 5단계 마법사 (welcome/vault/profile/samples/done) — Settings 영속 진행 |
| `Controllers::TutorialController` | `/tutorial` 4단계 학습 — IndexRepo 카운트로 자동 감지·진행 |
| `Controllers::GuidesController` | `/guides` 동기화 가이드 4종 (iCloud/OneDrive/Dropbox/Syncthing) 마크다운 → HTML 렌더 |
| `Controllers::SettingsController` | `/settings` — 프로필 / 경로·단축키 안내 / 백업 / 샘플 일괄 삭제 / 온보딩·튜토리얼 재실행 |
| `Controllers::PreviewController` | `POST /preview` Turbo Stream |
| `Controllers::ApiController` | `GET /api/wiki_complete`, `GET /api/tag_complete`, `GET /api/quick_search` (JSON) |

#### Frontend (Hotwire — 빌드 도구 0)
| 컨트롤러 | 역할 |
|------|------|
| `quick_memo_controller.js` (Stimulus) | 모달 + 단축키 + Turbo 제출 hook |
| `quick_search_controller.js` (Stimulus) | 글로벌 `Cmd/Ctrl+K` + 200ms 디바운스 fetch + ↑↓/Enter/Esc 키보드 내비게이션 |
| `editor_controller.js` (Stimulus) | CodeMirror 6 + textarea sync + `editor:input` event dispatch + 자동완성 (위키링크 + 태그) |
| `preview_controller.js` (Stimulus) | 디바운스 + fetch + `Turbo.renderStreamMessage` |

### Week 8 진행 상태 (Phase 1 마무리)

| 작업 | 상태 | 비고 |
|------|------|------|
| W8-T01 시스템 트레이 wrapper | ⏳ Deferred | 비-필수, 브라우저 진입으로 대체. Phase 9 MCP가 더 강한 대안 |
| W8-T02 Tebako 빌드 검증 | 🟡 스캐폴드 | `packaging/` 메타·드라이버 완료, 실제 빌드는 Tebako 환경 필요 |
| W8-T03 macOS DMG + codesign | ⏳ Deferred | Apple Developer 계정 필요 |
| W8-T04 Windows Inno Setup | ⏳ Deferred | Windows VM 필요 |
| W8-T05 Linux AppImage | ⏳ Deferred | linuxdeploy 환경 검증 필요 |
| W8-T06 `bin/sowing-doctor` 완성 | ✅ 완료 | 9개 섹션 + 진단 요약 (5+ 흔한 문제 자동 식별) |
| W8-T07 베타 테스터 모집 | ⏳ Deferred | 실제 사용자 5명 필요 |
| W8-T08 출시 준비 | 🟡 문서 완료 | CHANGELOG / RELEASE / KNOWN_ISSUES, GitHub Release는 바이너리 후 |

상세 일정은 [ROADMAP.md](ROADMAP.md) 참조 — Phase 1 (W1~W8) 과 Phase 2 (W9~W24) 모두 동일 문서에 정리됨.

## Phase 1 — 8주 개발 요약 (W1~W8 완료)

| 주 | 마일스톤 | 핵심 deliverable |
|----|---------|------------------|
| W1 | CLI 메모 + 옵시디언 호환 | Domain (Memo/Note/Record + ULID/TagSet), VaultRepo, IndexRepo, SafeWriter, Markdown Parser/Serializer, `bin/sowing memo` |
| W2 | 핵심 도메인 + 웹 UI 골격 | Sinatra modular + Hotwire, 메모/필기/기록 CRUD, 빠른 메모 모달(`Cmd+Shift+M`), CodeMirror 6 + 라이브 프리뷰 |
| W3 | 승격 + 위키링크 + 태그 | 메모→필기→기록 승격(ULID 유지), 위키링크 그래프 자동 동기화, 태그 클라우드, 자동완성(`[[`, `#`) |
| W4 | 검색 + 한국어 처리 | FTS5 trigram + 한국어 LIKE 폴백 (5,000건 < 500ms), 검색 화면 + 모든 필터, `Cmd+K` 빠른 검색 |
| W5 | 동기화 + 옵시디언 통합 | FileWatcher + self-write 필터, ReindexEntry, AdoptOrphan, ConsistencyCheck, 충돌 처리(낙관적 잠금) |
| W6 | 대시보드 + 통계 + 템플릿 | daily_stats + streak, 씨앗-숲 시각화 5단계 SVG, 템플릿 시스템 + 12종 교사 템플릿 |
| W7 | 온보딩 + 샘플 + 가이드 | 4단계 마법사, 12종 샘플 시드, 3분 인터랙티브 튜토리얼, 동기화 가이드 4종, 설정 화면 |
| W8 | 패키징 + QA (코드·문서) | Tebako 빌드 스캐폴드, doctor 9섹션, CHANGELOG / RELEASE / KNOWN_ISSUES |

**Phase 1 규모**: 13개 컨트롤러 · 86개 라우트 · 855건 spec pass · standardrb 0 issue · 5x stress 0 failures.

## Phase 2 — Software 3.0 전환 (W9~W24, 진행 예정)

| Week | Phase | 마일스톤 |
|------|-------|----------|
| W9~12 | Phase 9: Agent-Native Surface | MCP 서버 + audit log + agent 지침 — 외부 에이전트(Claude/ChatGPT/Codex)가 Sowing 직접 사용 |
| W13~16 | Phase 10: Eval Infrastructure | 한국어 교사 글 100건 코퍼스 + LLM-judge harness + CI 통합 |
| W17~20 | Phase 11: Tier-1 LLM 합성 | 학생별 누적 페이지 + 빠진 공백 알림 (LLM Wiki 패턴 진입) |
| W21~24 | Phase 12: Tier-2 LLM 합성 | 학기말 회고 합성 + 수업 패턴 + 모순 탐지 |

**기반**: Karpathy의 [Sequoia Ascent 2026 발표](sowing-docs/background.md) 12 명제로 Sowing 점검 결과 ([`sowing-docs/EVALUATION.md`](sowing-docs/EVALUATION.md)). 결정은 [ADR-013](docs/DECISIONS.md), 작업 분해는 [`ROADMAP.md`](ROADMAP.md) Phase 2 섹션, 진입자 안내는 [`KICKOFF.md` Phase 2](KICKOFF.md) 참조.

**명시적 거부 5종** (Phase 2 전 기간):
1. ❌ 챗봇 UI 절대 안 만듦
2. ❌ 자동 글쓰기 거부 (LLM이 사용자 대신 글 안 씀)
3. ❌ 클라우드 LLM 강제 안 함 (옵트인 + 로컬 LLM 동등 지원)
4. ❌ "AI가 ~ 생각합니다" 의인화 카피
5. ❌ 자율 에이전트의 vault 변경 (사용자 명시 수락 + audit log 의무)

## 문서

| 문서 | 대상 | 내용 |
|------|------|------|
| [SETUP.md](SETUP.md) | 개발자 | 개발 환경 설정 |
| [CLAUDE.md](CLAUDE.md) | Claude Code | 코드 작성 컨벤션 |
| [docs/SPEC.md](docs/SPEC.md) | 모든 기여자 | 전체 기술 명세 |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 모든 기여자 | 아키텍처 의사결정 기록 |
| [ROADMAP.md](ROADMAP.md) | 모든 기여자 | Phase 1 (W1~W8 완료) + Phase 2 (W9~W24 진행 예정) 작업 분해 |
| [KICKOFF.md](KICKOFF.md) | 신규 기여자 | Phase 1 첫 한 시간 + Phase 2 진입자 가이드 |
| [CHANGELOG.md](CHANGELOG.md) | 사용자·기여자 | 버전별 변경 이력 |
| [sowing-docs/background.md](sowing-docs/background.md) | Phase 2 기여자 | Karpathy Sequoia Ascent 2026 발표 — Phase 2 사상적 출발점 |
| [sowing-docs/EVALUATION.md](sowing-docs/EVALUATION.md) | Phase 2 기여자 | 12 명제 Sowing 평가 + Phase 9~12 로드맵 + 명시적 거부 |
| [docs/RELEASE.md](docs/RELEASE.md) | 운영자 | 출시 절차 / 핫픽스 / 롤백 |
| [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) | 사용자 | 알려진 한계 (패키징·기능·보안·성능) |
| [docs/AGENT_GUIDE.md](docs/AGENT_GUIDE.md) | MCP 사용자 | Claude Desktop / Codex / Continue / Zed 등록 + 12개 도구 + 5종 프롬프트 |
| [packaging/README.md](packaging/README.md) | 운영자 | Tebako 빌드 단계 + OS별 deferred 항목 |

## 라이선스

MIT
