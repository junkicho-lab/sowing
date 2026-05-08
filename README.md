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

## 구현 현황 (Week 2 완료)

### ✅ 동작하는 기능

- **웹 UI** (`bin/sowing dev` → `http://127.0.0.1:48723`)
  - 한국어 대시보드: 최근 메모 5건 + 빈 상태 안내
  - 빠른 메모 모달: `Cmd/Ctrl+Shift+M` 호출, `Cmd/Ctrl+Enter` 저장, Turbo Stream으로 즉시 반영
  - 메모 목록 (`/memos`): 페이지네이션 30건/page, 100건 < 200ms
  - 필기 CRUD (`/notes`): 카테고리 4종(수업/연수/도서/회의) + 출처 필수 + 편집 시 path 이동(휴지통 보존)
  - 기록 CRUD (`/records`): 자유 카테고리 + datalist + `30_Records/{YYYY}/{category}/` + promoted_from
  - 마크다운 에디터: CodeMirror 6 (line wrapping, syntax highlight, basicSetup)
  - 라이브 프리뷰: 좌-우 split, Turbo Stream + 300ms 디바운스, 서버 응답 ~2ms
- **CLI**: `bin/sowing memo "내용"`, `bin/sowing-doctor`
- **테스트**: `bundle exec rspec` (387건 통과)

### 구현된 컴포넌트

#### Domain (외부 의존 0)
| 모듈 | 설명 |
|------|------|
| `Domain::ValueObjects::{Ulid, TagSet}` | 불변 Value Object, frozen, 한국어 정렬 |
| `Domain::{Memo, Note, Record}` + `Entry` mixin | 3종 도메인, `to_frontmatter`/`to_markdown` |

#### Infrastructure
| 모듈 | 설명 |
|------|------|
| `Filesystem::SafeWriter` | 원자적 쓰기 (tempfile + rename), NFC 정규화, chaos test 통과 |
| `Markdown::{Parser, Serializer, ParsedDocument}` | front_matter_parser 래핑, round-trip 검증 |
| `Paths`, `DB` | OS별 경로, Sequel + SQLite 연결 (PRAGMA WAL/foreign_keys) |

#### Repository (단방향 의존 — Domain → Repo → Infra)
| 모듈 | 설명 |
|------|------|
| `Repositories::VaultRepo` | `write/read/list/delete(→trash)/update(path 이동)` |
| `Repositories::IndexRepo` + `IndexedEntry` | CRUD + tags 정규화 + category·date 검색 + paging + distinct categories |

#### Use Case (Dry::Monads Result)
| 모듈 | 설명 |
|------|------|
| `UseCases::Persistence` | 공통 mixin: `persist!` / `repersist!` / `update_index!` |
| `UseCases::{Create,Update}{Memo,Note,Record}` | 5개 Use Case (Memo는 Update 미구현) |

#### Web (Sinatra modular)
| 모듈 | 라우트 |
|------|------|
| `Controllers::ApplicationController` | base — views/public/helpers (markdown, escape, 한국어 날짜) |
| `Controllers::DashboardController` | `GET /` |
| `Controllers::MemosController` | `GET/POST /memos`, `POST` Turbo Stream |
| `Controllers::NotesController` | 6 actions (`index/new/create/show/edit/update`) |
| `Controllers::RecordsController` | 6 actions |
| `Controllers::PreviewController` | `POST /preview` Turbo Stream |

#### Frontend (Hotwire — 빌드 도구 0)
| 컨트롤러 | 역할 |
|------|------|
| `quick_memo_controller.js` (Stimulus) | 모달 + 단축키 + Turbo 제출 hook |
| `editor_controller.js` (Stimulus) | CodeMirror 6 + textarea sync + `editor:input` event dispatch |
| `preview_controller.js` (Stimulus) | 디바운스 + fetch + `Turbo.renderStreamMessage` |

### 미구현 (Week 3 이후)

- 위키링크 `[[link]]`·`[[link\|alias]]` 파서·렌더러·그래프 (W3-T01~02)
- 위키링크 자동완성 (W3-T03~04)
- 태그 페이지 + 메모 → 필기/기록 승격 UI (W3-T05~07)
- 전문 검색 (FTS5, 한국어 토큰화 — W4)
- 옵시디언 ↔ 본 앱 동기화 (파일 watcher — W5+)
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
