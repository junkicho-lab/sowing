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

- Ruby 3.3 + Sinatra 4
- SQLite (인덱스), 로컬 마크다운 파일 (콘텐츠)
- Hotwire (Turbo + Stimulus)
- Tebako 단일 실행파일 패키징

## 시작하기

### 사용자 (출시 후)

[Releases 페이지](https://github.com/your-org/sowing/releases)에서 OS별 인스톨러를 다운로드하세요.

### 개발자

[`SETUP.md`](SETUP.md) 를 참조하세요.

## 구현 현황 (Week 5 완료)

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
- **CLI**: `bin/sowing memo "내용"`, `bin/sowing-doctor`
- **테스트**: `bundle exec rspec` (719건 통과)

### 구현된 컴포넌트

#### Domain (외부 의존 0)
| 모듈 | 설명 |
|------|------|
| `Domain::ValueObjects::{Ulid, TagSet}` | 불변 Value Object, frozen, 한국어 정렬 |
| `Domain::{Memo, Note, Record}` + `Entry` mixin | 3종 도메인, `to_frontmatter`/`to_markdown` |

#### Infrastructure
| 모듈 | 설명 |
|------|------|
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
| `Repositories::IndexRepo` + `IndexedEntry` | CRUD + tags 정규화 + category·date 검색 + paging + distinct categories + 위키링크 그래프 (outbound·inbound·broken·자동 re-link) + tag_cloud + complete/complete_tags + `search_with_filters` (FTS5↔LIKE 자동 라우팅, 한글 비율 ≥ 30% → LIKE) |

#### Use Case (Dry::Monads Result)
| 모듈 | 설명 |
|------|------|
| `UseCases::Persistence` | 공통 mixin: `persist!` / `repersist!` / `update_index!` |
| `UseCases::{Create,Update}{Memo,Note,Record}` | 5개 CRUD Use Case (Memo는 Update 미구현) — Update*는 `expected_file_hash`로 낙관적 잠금 + `force` 시 `.sowing/conflicts/` 백업 |
| `UseCases::{PromoteToNote, PromoteToRecord}` | 메모/필기 승격 — ID 유지, path 이동, promoted_from 자동 |
| `UseCases::ReindexEntry` | 외부 변경(:added/:modified/:removed) → 인덱스 동기화, mtime+hash 비교로 unchanged 단축 |
| `UseCases::AdoptOrphan` | frontmatter 없는 외부 파일 → path 기반 mode 추론 + ULID 부여 + in-place frontmatter 기록 |
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
| `Controllers::PreviewController` | `POST /preview` Turbo Stream |
| `Controllers::ApiController` | `GET /api/wiki_complete`, `GET /api/tag_complete`, `GET /api/quick_search` (JSON) |

#### Frontend (Hotwire — 빌드 도구 0)
| 컨트롤러 | 역할 |
|------|------|
| `quick_memo_controller.js` (Stimulus) | 모달 + 단축키 + Turbo 제출 hook |
| `quick_search_controller.js` (Stimulus) | 글로벌 `Cmd/Ctrl+K` + 200ms 디바운스 fetch + ↑↓/Enter/Esc 키보드 내비게이션 |
| `editor_controller.js` (Stimulus) | CodeMirror 6 + textarea sync + `editor:input` event dispatch + 자동완성 (위키링크 + 태그) |
| `preview_controller.js` (Stimulus) | 디바운스 + fetch + `Turbo.renderStreamMessage` |

### 미구현 (Week 6 이후)

- 대시보드 + 통계 + 템플릿 (W6)
- 온보딩 + 샘플 콘텐츠 + 동기화 가이드 (W7)
- 패키징 (Tebako 단일 실행파일 — W8)

상세 일정은 [ROADMAP.md](ROADMAP.md) 참조.

## 문서

| 문서 | 대상 | 내용 |
|------|------|------|
| [SETUP.md](SETUP.md) | 개발자 | 개발 환경 설정 |
| [CLAUDE.md](CLAUDE.md) | Claude Code | 코드 작성 컨벤션 |
| [docs/SPEC.md](docs/SPEC.md) | 모든 기여자 | 전체 기술 명세 |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 모든 기여자 | 아키텍처 의사결정 기록 |
| [ROADMAP.md](ROADMAP.md) | 모든 기여자 | 8주 MVP 일정 및 작업 분해 |

## 라이선스

MIT
