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

## 구현 현황 (Week 1 완료)

### ✅ 동작하는 기능

- **CLI에서 메모 작성**: `bin/sowing memo "내용"` → `00_Inbox/YYYY-MM-DD_HHmmss.md` 생성 + SQLite 인덱스 갱신
- **개발 서버**: `bin/sowing dev` → `http://127.0.0.1:48723`
- **진단 도구**: `bin/sowing-doctor`
- **테스트**: `bundle exec rspec` (192건 통과)

### 구현된 컴포넌트

| 계층 | 모듈 | 설명 |
|------|------|------|
| Domain | `Sowing::Domain::ValueObjects::{Ulid, TagSet}` | 불변 Value Object, frozen, 한국어 정렬 |
| Domain | `Sowing::Domain::{Memo, Note, Record}` + `Entry` mixin | 메모/필기/기록 3종, `to_frontmatter`/`to_markdown` |
| Infrastructure | `Filesystem::SafeWriter` | 원자적 쓰기 (tempfile + rename), NFC 정규화 |
| Infrastructure | `Markdown::{Parser, Serializer, ParsedDocument}` | front_matter_parser 래핑, 양방향 round-trip 검증 |
| Repository | `Repositories::VaultRepo` | 마크다운 파일 시스템 (write/read/list/delete=trash) |
| Repository | `Repositories::IndexRepo` + `IndexedEntry` | SQLite 인덱스 CRUD + 태그·날짜 검색 |
| Use Case | `UseCases::CreateMemo` | 도메인 + 두 Repo 조립, Dry::Monads Result |
| Infrastructure | `Paths`, `DB` | OS별 경로 결정, Sequel + SQLite 연결 |

### 미구현 (Week 2 이후)

- 웹 UI (메모/필기/기록 작성·조회 — Sinatra 컨트롤러 + Hotwire)
- 마크다운 에디터 (CodeMirror 6)
- 위키링크 `[[link]]` 파서·자동완성·그래프
- 전문 검색 (FTS5, 한국어 토큰화)
- 옵시디언 ↔ 본 앱 동기화 (파일 watcher)
- 패키징 (Tebako 단일 실행파일)

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
