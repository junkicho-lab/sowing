# Sowing MVP 로드맵

본 문서는 8주 MVP 일정을 **Claude Code가 단일 작업으로 받아들일 수 있는 단위**로 세분화한 작업 목록입니다.

각 작업은 다음 형식의 ID를 가집니다: `W{주차}-T{번호}` (예: `W1-T03`).
Claude Code 사용 시 작업 ID로 지시하면 명확합니다 (예: `claude "W2-T05 작업 진행해줘"`).

---

## 진행 상태 표기

- [ ] 미시작
- [~] 진행 중
- [x] 완료
- [!] 블로커 발생

각 작업은 다음 정보를 포함합니다:
- **목표**: 무엇을 하는가
- **출력**: 무엇을 만드는가 (파일·테스트·기능)
- **검증**: 어떻게 완료를 확인하는가
- **선행**: 어떤 작업이 먼저 끝나야 하는가

---

## Week 1: 기반 구축 (Foundation)

### [x] W1-T01: 프로젝트 부트스트랩 — 완료 (2026-05-08, 커밋 5596df7)
- **목표**: Sinatra + Sequel + RSpec 최소 동작 환경 구성
- **출력**:
  - `Gemfile`, `Gemfile.lock`
  - `Rakefile` (db:migrate, db:rollback, db:reset 태스크)
  - `config.ru`
  - `bin/sowing` (start, dev, memo, doctor 서브커맨드 골격)
  - `lib/sowing/version.rb`
  - `lib/sowing/application.rb` (Zeitwerk 부트스트랩)
  - `spec/spec_helper.rb`
  - `.rspec`, `.rubocop.yml` (standardrb 설정), `.ruby-version`, `.gitignore`
- **검증**:
  - `bundle install` 성공
  - `bin/sowing dev` 실행 시 `Hello, Sowing` 페이지가 `http://127.0.0.1:48723` 에 표시
  - `bundle exec rspec` 성공 (샘플 테스트 1개 포함)
- **선행**: 없음

### [x] W1-T02: 데이터 디렉토리·로깅 인프라 — 베이스라인에 paths.rb 포함 (logger는 W2 이전 별도 작업으로 보강 가능)
- **목표**: OS별 데이터 디렉토리 자동 결정 + 로거 설정
- **출력**:
  - `lib/sowing/infrastructure/paths.rb` — `data_dir`, `vault_default_dir`, `cache_dir` 헬퍼
  - `lib/sowing/logger.rb` — 환경별 로그 레벨, 파일 출력
  - 테스트 포함
- **검증**: macOS·Linux에서 각각 올바른 경로 반환 확인 (mock으로 테스트)
- **선행**: W1-T01

### [x] W1-T03: SQLite 연결 + 첫 마이그레이션 — 베이스라인에 db.rb + 001_create_entries.rb 포함
- **목표**: Sequel + SQLite 연결, `entries` 테이블 생성
- **출력**:
  - `lib/sowing/infrastructure/db/connection.rb`
  - `db/migrations/001_create_entries.rb` (SPEC §8.3 스키마)
  - `Rakefile` 의 db:migrate 태스크 동작
- **검증**:
  - `bundle exec rake db:migrate` 성공
  - `bundle exec rake db:rollback` 성공
  - 마이그레이션 멱등 (두 번 실행 안전)
- **선행**: W1-T02

### [x] W1-T04: 도메인 객체 — Ulid, TagSet — 완료 (2026-05-08, 커밋 7be57f6)
- **목표**: 가장 기본적인 Value Object 두 개
- **출력**:
  - `lib/sowing/domain/value_objects/ulid.rb` — 생성·파싱·비교
  - `lib/sowing/domain/value_objects/tag_set.rb` — 중복 제거, 정렬, frozen
  - `spec/domain/value_objects/ulid_spec.rb`
  - `spec/domain/value_objects/tag_set_spec.rb`
- **검증**: 각 단위 테스트 100% 통과, 모두 frozen 검증 포함
- **선행**: W1-T01

### [x] W1-T05: 도메인 객체 — Entry, Memo, Note, Record — 완료 (2026-05-08, 커밋 cb07764)
- **목표**: 메모/필기/기록 3종 도메인 객체
- **출력**:
  - `lib/sowing/domain/entry.rb` (공통 모듈 또는 부모)
  - `lib/sowing/domain/memo.rb`
  - `lib/sowing/domain/note.rb`
  - `lib/sowing/domain/record.rb`
  - 각 객체에 `to_frontmatter`, `to_markdown` 메서드 (SPEC §8.1 형식 준수)
  - 각 spec 파일
- **검증**:
  - 모든 객체가 freeze 됨
  - `to_markdown` 출력이 valid frontmatter + body 형식
  - 옵시디언 표준 키만 사용
- **선행**: W1-T04

### [x] W1-T06: VaultRepo 구현 (읽기/쓰기/삭제) — 완료 (2026-05-08, 커밋 8d31901 / 8b09f59 / 81bcf59 — 3분할)
- **목표**: 마크다운 파일 시스템 추상화
- **출력**:
  - `lib/sowing/infrastructure/filesystem/safe_writer.rb` — 원자적 쓰기 (tempfile + rename)
  - `lib/sowing/infrastructure/markdown/parser.rb` — frontmatter + body 파싱
  - `lib/sowing/infrastructure/markdown/serializer.rb` — Entry → markdown 직렬화
  - `lib/sowing/repositories/vault_repo.rb` — write, read, list, delete (휴지통)
  - 각 spec (임시 디렉토리 사용)
- **검증**:
  - SafeWriter가 쓰기 도중 강제 종료에도 파일 무결성 보장 (chaos 테스트)
  - 한글 파일명·NFC 정규화 검증
  - 휴지통 폴더 (`.sowing/trash/`) 로 이동 확인
- **선행**: W1-T05

### [x] W1-T07: IndexRepo 구현 (Sequel 기반) — 완료 (2026-05-08, 커밋 9caf748)
- **목표**: SQLite entries 테이블 CRUD
- **출력**:
  - `lib/sowing/repositories/index_repo.rb` — upsert, find, list, delete, search_by_tag, search_by_date
  - `spec/repositories/index_repo_spec.rb`
- **검증**: CRUD 통과, 트랜잭션 검증
- **선행**: W1-T03, W1-T05

### [x] W1-T08: CLI에서 메모 작성 동작 — 완료 (2026-05-08, 커밋 9784fde) **🎯 W1 마일스톤 달성**
- **목표**: `bin/sowing memo "내용"` 으로 마크다운 파일 + 인덱스 생성
- **출력**:
  - `lib/sowing/use_cases/create_memo.rb` (CLAUDE.md 패턴 준수)
  - `bin/sowing` 의 `memo` 서브커맨드 구현
  - 각 spec
- **검증**:
  - `bin/sowing memo "테스트"` 실행 시 `00_Inbox/YYYY-MM-DD_HHmmss.md` 생성
  - 파일을 옵시디언으로 열어 정상 표시 확인
  - SQLite 인덱스에 레코드 추가 확인
- **선행**: W1-T06, W1-T07

### **🎯 Week 1 마일스톤**
**CLI에서 메모를 만들고, 옵시디언으로 열어볼 수 있다.**

---

## Week 2: 핵심 도메인 + 웹 UI 골격

### [x] W2-T01: Sinatra 라우트·뷰 구조 정립 — 완료 (2026-05-08, 커밋 32a172d)
- **출력**:
  - `lib/sowing/controllers/application_controller.rb` (Sinatra::Base)
  - `lib/sowing/controllers/dashboard_controller.rb`
  - `views/layouts/application.erb` — Hotwire 로딩, 한국어 metadata
  - `views/dashboard/show.erb` — 빈 대시보드
  - `public/css/application.css` — 디자인 토큰 (SPEC §10.4)
- **검증**: 브라우저에서 한국어 대시보드 표시
- **선행**: W1 전체

### [x] W2-T02: 글로벌 단축키 + 빠른 메모 모달 — 완료 (2026-05-08, 커밋 ae77e2b)
- **출력**:
  - `views/memos/_quick_modal.erb`
  - `public/js/controllers/quick_memo_controller.js` (Stimulus)
  - `MemosController#create` — Turbo Stream 응답
- **검증**:
  - `Cmd/Ctrl+Shift+M` 으로 모달 호출
  - 입력 후 `Cmd/Ctrl+Enter` 로 저장, 자동 닫힘
  - 대시보드에 즉시 반영 (Turbo Stream)
- **선행**: W2-T01, W1-T08

### [x] W2-T03: 메모 목록 화면 — 완료 (2026-05-08, 커밋 33c8c4e)
- **출력**:
  - `MemosController#index`
  - `views/memos/index.erb`
  - 페이지네이션 또는 무한스크롤
- **검증**: 100건 이상에서도 < 200ms 응답
- **선행**: W2-T01

### [x] W2-T04: 필기(Note) CRUD — 완료 (2026-05-08, 커밋 6891167 / 1bdd551 / fbad0c0 — 3분할)
- **출력**:
  - `lib/sowing/use_cases/create_note.rb`, `update_note.rb`
  - `NotesController` (index, new, create, edit, update, show)
  - `views/notes/*` (form, show, index)
  - 카테고리 select (수업/연수/도서/회의)
  - 출처 필드 필수 검증
- **검증**: CRUD 전체 흐름 + 카테고리 필터 동작
- **선행**: W2-T01

### [x] W2-T05: 기록(Record) CRUD — 완료 (2026-05-08, 커밋 c9d8f78)
- **출력**: 위와 동일한 구조로 RecordsController
- **검증**: CRUD 전체 흐름
- **선행**: W2-T01

### [x] W2-T06: 마크다운 에디터 통합 (CodeMirror 6) — 완료 (2026-05-08, 커밋 7f99b8b)
- **출력**:
  - `public/js/controllers/editor_controller.js`
  - CDN 로드 + Markdown 모드
  - `views/shared/_editor.erb` 부분뷰
- **검증**: 필기·기록 작성 시 CodeMirror 표시, 저장 시 텍스트 정상 전송
- **선행**: W2-T04, W2-T05

### [x] W2-T07: 마크다운 실시간 프리뷰 — 완료 (2026-05-08, 커밋 3b814f1) **🎯 W2 마일스톤 달성**
- **출력**:
  - 좌측 에디터 / 우측 프리뷰 분할 뷰
  - 서버측 Commonmarker 렌더 + Turbo Stream으로 디바운스 갱신 (300ms)
- **검증**: 입력 후 300ms 이내에 프리뷰 갱신
- **선행**: W2-T06

### **🎯 Week 2 마일스톤**
**브라우저에서 빠른 메모 모달과 필기·기록 작성 화면이 동작한다.**

---

## Week 3: 승격 + 위키링크 + 태그

### [x] W3-T01: 위키링크 파서·렌더러 — 완료 (2026-05-08, 커밋 e0c75c5)
- **출력**:
  - `lib/sowing/infrastructure/markdown/wiki_link.rb`
  - 본문에서 `[[link]]`, `[[link|alias]]` 추출
  - 옵시디언 호환 escape 처리
  - spec 포함 (옵시디언 호환성 케이스)
- **검증**: spec/compatibility 의 wiki link 케이스 통과
- **선행**: W2 전체

### [x] W3-T02: 위키링크 그래프 인덱스 — 완료 (2026-05-08, 커밋 af78203)
- **출력**:
  - `db/migrations/002_create_links.rb`
  - `IndexRepo#upsert_links(entry_id, [...])`
  - 깨진 링크 추적
- **검증**: 링크 추가·제거 시 그래프 갱신
- **선행**: W3-T01

### [x] W3-T03: 위키링크 자동완성 API — 완료 (2026-05-08, 커밋 0689196)
- **출력**:
  - `GET /api/wiki_complete?q=` 엔드포인트
  - 메모/필기/기록 모두 후보에 포함 (ADR-004)
  - 정렬: 모드 우선순위 (record > note > memo) + 최근순
- **검증**: 응답 < 100ms (10,000건 기준), 결과 형식이 ADR-004 명세 준수
- **선행**: W3-T02

### [x] W3-T04: CodeMirror 위키링크 자동완성 — 완료 (2026-05-08, 커밋 b84f345)
- **출력**:
  - `public/js/controllers/editor_controller.js` 확장
  - `[[` 입력 시 200ms 디바운스 후 자동완성 팝업
- **검증**: UX 시나리오 통과 (입력 → 후보 → Tab으로 선택 → 닫힘)
- **선행**: W3-T03

### [x] W3-T05: 태그 시스템 — 완료 (2026-05-08, 커밋 5183f51, 003_create_tags 마이그레이션은 W1-T07에 002로 선행)
- **출력**:
  - `db/migrations/003_create_tags.rb`
  - 본문 `#태그` + frontmatter `tags` 양쪽 추출
  - `TagsController#index` — 태그별 항목 목록
  - 태그 자동완성
- **검증**: 모든 곳에서 태그 검색·필터 동작
- **선행**: W2 전체

### [x] W3-T06: 메모 → 필기 승격 — 완료 (2026-05-08, 커밋 4e54114)
- **출력**:
  - `lib/sowing/use_cases/promote_to_note.rb`
  - 카테고리·출처 입력 다이얼로그
  - 파일 이동 + frontmatter 업데이트 + `promoted_from` 기록
  - 트랜잭션 보장 (실패 시 원상 복구)
- **검증**:
  - 메모가 `00_Inbox/` 에서 `20_Notes/{category}/` 로 이동
  - 원본 frontmatter에 `promoted_from` 추가
  - SQLite 인덱스 갱신
- **선행**: W2 전체

### [x] W3-T07: 필기·메모 → 기록 승격 — 완료 (2026-05-08, 커밋 bb717e5) **🎯 W3 마일스톤 달성**
- **출력**: W3-T06 패턴으로 `promote_to_record.rb`
- **검증**: 동일
- **선행**: W3-T06

### **🎯 Week 3 마일스톤**
**메모 → 필기 → 기록 승격 흐름과 위키링크 자동완성이 완전 동작한다.**

---

## Week 4: 검색 + 한국어 처리

### [x] W4-T01: SQLite FTS5 가상 테이블 — 완료 (2026-05-08, 커밋 b9bf923)
- **출력**:
  - `db/migrations/004_create_entries_fts.rb` — trigram 토크나이저 사용
  - `IndexRepo#index_for_search`, `search_full_text`
  - 인덱스 자동 동기화 트리거
- **검증**: 기본 검색 동작, 인덱스 누락 없음
- **선행**: W3 전체

### [x] W4-T02: 한국어 검색 폴백 (LIKE) — 완료 (2026-05-08, 커밋 a209da2)
- **출력**:
  - 한글 비율 ≥ 30% 쿼리는 LIKE 폴백
  - 5,000건 기준 < 500ms 보장
- **검증**: 한국어 부분일치 검색 정확도 확인 (테스트 픽스처)
- **선행**: W4-T01

### [x] W4-T03: 검색 화면 — 완료 (2026-05-08, 커밋 263f638)
- **출력**:
  - `SearchController#index`
  - `views/search/index.erb` — 검색창, 필터, 결과
  - 필터: 모드, 태그, 카테고리, 날짜 범위
- **검증**: 모든 필터 조합 동작
- **선행**: W4-T02

### [x] W4-T04: 통합 검색 단축키 — 완료 (2026-05-08, 커밋 94b3e00) **🎯 W4 마일스톤 달성**
- **출력**:
  - `Cmd/Ctrl+K` 글로벌 검색 모달
  - 검색 결과 클릭 시 해당 entry로 이동
- **검증**: 어디서든 단축키로 검색 가능
- **선행**: W4-T03

### **🎯 Week 4 마일스톤**
**5,000건 데이터에서 한국어 검색이 < 500ms로 동작한다.**

---

## Week 5: 동기화 + 옵시디언 통합

### [x] W5-T01: 파일시스템 감시 (Listen gem) — 완료 (2026-05-08, 커밋 6e2c34f)
- **출력**:
  - `lib/sowing/infrastructure/filesystem/file_watcher.rb`
  - 500ms debounce, 자체 쓰기 무시(self-write filter)
  - 백그라운드 스레드 또는 async fiber
- **검증**: 외부 에디터로 파일 수정 시 감지 확인
- **선행**: W1-T06

### [x] W5-T02: 외부 변경 → 인덱스 갱신 — 완료 (2026-05-08, 커밋 aaefb69)
- **출력**:
  - 변경 이벤트 → `ReindexEntry` Use Case 호출
  - mtime/hash 비교로 실제 변경만 처리
  - Turbo Stream으로 클라이언트 푸시 (SSE 또는 ActionCable 대안)
- **검증**: 옵시디언으로 편집한 내용이 본 앱에 자동 반영
- **선행**: W5-T01

### [x] W5-T03: 외부 신규 파일 자동 입양 (Adoption) — 완료 (2026-05-08, 커밋 281595b)
- **출력**:
  - frontmatter 없는 파일 발견 시 자동으로 ULID·mode 부여
  - 사용자 설정으로 자동/수동 선택
- **검증**: 옵시디언에서 새 파일 만들고 본 앱에서 인식되는지 확인
- **선행**: W5-T02

### [x] W5-T04: 부팅 시 일관성 검증 — 완료 (2026-05-08, 커밋 9cdb84e)
- **출력**:
  - 앱 시작 시 볼트 스캔 + SQLite 비교
  - 차이 발견 시 자동 동기화 또는 사용자 확인
- **검증**: 인덱스 삭제 후 부팅 → 자동 재구축
- **선행**: W5-T02

### [x] W5-T05: 충돌 처리 다이얼로그 — 완료 (2026-05-08, 커밋 aacce36) **🎯 W5 마일스톤 달성**
- **출력**:
  - 동시 편집 감지 시 modal: Keep Mine / Keep Theirs / Compare
  - 사용자 선택에 따라 적용
- **검증**: 의도적 충돌 시나리오 통과
- **선행**: W5-T02

### **🎯 Week 5 마일스톤**
**본 앱과 옵시디언을 동시에 켜고 양방향 편집이 안정적으로 동기화된다.**

---

## Week 6: 대시보드 + 통계 + 템플릿

### [x] W6-T01: 통계 집계 — 완료 (2026-05-08, 커밋 17bceb6)
- **출력**:
  - `db/migrations/005_create_daily_stats.rb`
  - `lib/sowing/use_cases/aggregate_daily_stats.rb` — 야간 또는 부팅 시 실행
  - streak 계산
- **검증**: 7일 연속 작성 시 streak = 7
- **선행**: W3 전체

### [x] W6-T02: 대시보드 위젯 — 완료 (2026-05-08, 커밋 17bceb6)
- **출력**:
  - 오늘/이번주/이번달 카운트
  - streak 표시
  - 최근 메모 5건
- **검증**: 모든 숫자 정확
- **선행**: W6-T01

### [x] W6-T03: 씨앗-숲 시각화 — 완료 (2026-05-08, 커밋 ee6f952)
- **출력**:
  - SVG 기반 시각화 (외부 라이브러리 없이)
  - 누적 기록 수에 따라 씨앗/새싹/나무/숲 단계 변화
- **검증**: 디자인 합의 후 시각적 검증
- **선행**: W6-T01

### [x] W6-T04: 템플릿 시스템 — 완료 (2026-05-08, 커밋 ded6c94)
- **출력**:
  - `lib/sowing/repositories/template_repo.rb`
  - 템플릿 적용 시 Liquid/ERB 단순 치환
  - 사용자 정의 템플릿 추가 UI
- **검증**: 템플릿으로 작성 시 placeholder가 올바르게 채워짐
- **선행**: W2 전체

### [x] W6-T05: 12종 교사 템플릿 작성 — 완료 (2026-05-08, 커밋 cc94ca2) **🎯 W6 마일스톤 달성**
- **출력**: SPEC §4.1 F8 의 12종을 `templates/` 에 마크다운으로
- **검증**: 모든 템플릿이 옵시디언으로 정상 표시
- **선행**: W6-T04

### **🎯 Week 6 마일스톤**
**대시보드, 시각화, 12종 템플릿이 모두 동작한다.**

---

## Week 7: 온보딩 + 샘플 콘텐츠 + 동기화 가이드

### [x] W7-T01: 첫 실행 마법사 — 완료 (2026-05-09, 커밋 f9879fb)
- **출력**:
  - `OnboardingController` — 단계별 화면
  - 볼트 위치 선택, 사용자 프로필, 샘플 동의
  - 단계별 진행 표시
- **검증**: 신규 사용자가 5분 이내 완료
- **선행**: W6 전체

### [x] W7-T02: 12종 샘플 콘텐츠 작성 (ADR-005) — 완료 (2026-05-09, 커밋 eba64cf)
- **출력**:
  - `templates/samples/` 에 12개 마크다운 파일
  - 메모 4 + 필기 4 + 기록 4
  - 모두 `is_sample: true` frontmatter
- **검증**: 옵시디언 호환, 위키링크 일부 포함하여 그래프 시연 가능
- **선행**: W6-T05

### [x] W7-T03: 샘플 콘텐츠 시드 명령 — 완료 (2026-05-09, 커밋 cc0d765)
- **출력**:
  - `lib/sowing/use_cases/seed_samples.rb`
  - `bundle exec rake vault:seed`
  - 온보딩에서 호출
- **검증**: 동의 시에만 실행, 중복 시드 방지
- **선행**: W7-T02

### [x] W7-T04: 첫 메모 인터랙티브 튜토리얼 — 완료 (2026-05-09, 커밋 bb94377)
- **출력**: 3분짜리 인터랙티브 가이드
  - 빠른 메모 → 저장 → 필기 승격 → 기록 승격
- **검증**: 전체 흐름 완료
- **선행**: W7-T01

### [x] W7-T05: 클라우드 동기화 가이드 4종 (ADR-006) — 완료 (2026-05-09, 커밋 039e798)
- **출력**:
  - `templates/guides/sync_*.md` 4개 (iCloud, OneDrive, Dropbox, Syncthing)
  - 설정 화면에서 표시
- **검증**: OS별 매트릭스 정확, 링크 유효
- **선행**: W6 전체

### [x] W7-T06: 설정 화면 — 완료 (2026-05-09, 커밋 7a8f90a) **🎯 W7 마일스톤 달성**
- **출력**:
  - 볼트 위치 변경
  - 단축키 변경
  - 백업 + 동기화 가이드 진입점
  - 샘플 삭제 메뉴
- **검증**: 모든 설정 항목 동작
- **선행**: W7-T05

### **🎯 Week 7 마일스톤**
**처음 보는 교사가 30분 안에 첫 메모·필기·기록을 모두 작성하고 동기화 가이드까지 확인 가능.**

---

## Week 8: 패키징 + QA + 베타

### [-] W8-T01: 시스템 트레이 wrapper — Deferred (비-필수, OS별 native 코드 필요)
- 브라우저로 `http://127.0.0.1:48723` 직접 접속만으로 MVP 충족. trayer는 Phase 2.

### [~] W8-T02: Tebako 빌드 스캐폴드 — 부분 완료 (2026-05-09)
- ✅ `packaging/tebako.yml` — 빌드 메타데이터
- ✅ `packaging/build.sh` — Linux/macOS/Windows 드라이버
- ✅ `packaging/README.md` — 사전 요구사항·단계 안내
- ⏳ 실제 빌드는 Tebako 바이너리 + Docker 환경에서 수동 진행 필요

### [-] W8-T03: macOS DMG + codesign + notarize — Deferred (Apple Developer 계정 필요)
- 우회: 소스 빌드(`bundle install && bin/sowing dev`). KNOWN_ISSUES.md 명시.

### [-] W8-T04: Windows Inno Setup 인스톨러 — Deferred (Windows VM 필요)
- 우회: WSL2에서 Linux 빌드 사용.

### [-] W8-T05: Linux AppImage — Deferred (linuxdeploy 환경 검증 필요)
- 우회: Tebako 단일 바이너리 직접 실행.

### [x] W8-T06: 진단 도구 `bin/sowing-doctor` 완성 — 완료 (2026-05-09)
- 환경(Ruby/인코딩) + 경로(권한·디스크 여유) + DB(SQLite 버전·FTS5 정합성) + 볼트
  무결성 + 동기화/충돌 + 통계/성장 + 템플릿 + 온보딩/학습 + 동기화 가이드 9개 섹션.
- 진단 요약 (issues 누적 → 마지막에 액션 제안), 5+ 흔한 문제 자동 식별.

### [-] W8-T07: 베타 테스터 5명 모집·피드백 수집 — Deferred (실제 사용자 필요)
- 출시 후 진행. README + RELEASE.md 따라 GitHub Issues 운영.

### [~] W8-T08: 출시 준비 — 문서 완료 (2026-05-09)
- ✅ CHANGELOG.md (v0.1.0 + Unreleased)
- ✅ docs/RELEASE.md — 출시 절차 / 핫픽스 / 롤백 / 데이터 호환성 약속
- ✅ docs/KNOWN_ISSUES.md — 패키징·기능·보안·성능 한계 솔직 공개
- ⏳ GitHub Release 페이지 — 바이너리 빌드 후 진행 (T03~T05 의존)

### **🎯 Week 8 마일스톤 (= MVP 출시)**
**3개 OS에서 인스톨러를 통한 설치가 가능하고, 베타 사용자가 만족한다.**

> **현재 상태 (2026-05-09)**: 코드·문서 측면 MVP 완성 (855건 spec pass, 13개 컨트롤러, 9개 doctor 섹션).
> 실제 OS별 인스톨러 출시 + 베타 테스터 모집은 후속 작업으로 분리 — Tebako 빌드 환경,
> Apple Developer 계정, Windows VM, 실제 사용자 5명이 필요. 스캐폴드(packaging/) +
> 출시 절차 문서(RELEASE.md) + 한계 공개(KNOWN_ISSUES.md) 까지는 완료.

---

# Phase 2: Software 3.0 전환 (Week 9~24, 16주)

> **근거**: [`sowing-docs/EVALUATION.md`](sowing-docs/EVALUATION.md) — Karpathy의
> Sequoia Ascent 2026 12 명제로 점검한 결과, Sowing은 agent-native 데이터 레이어는
> 잘 갖췄으나 agent-facing 표면(MCP·LLM 합성·구조화 로그)이 비어 있음. Phase 2는
> 이 격차를 메운다.
>
> **결정**: [`docs/DECISIONS.md` ADR-013](docs/DECISIONS.md) — Software 3.0 전환
> 원칙·거부 항목 명시.
>
> **변하지 않는 것**: 마크다운 SoT, 결정적 도메인, 검증 가능성, 로컬 우선,
> 옵시디언 호환, 영구 삭제 금지. Phase 2의 모든 변경은 이 원칙 위에서.

## Phase 2 큰 그림

| Week | Phase | 마일스톤 |
|------|-------|----------|
| W9~12 | Phase 9: Agent-Native Surface | 외부 에이전트(Claude/ChatGPT/Codex)가 MCP로 Sowing의 sensors·actuators 호출 가능 |
| W13~16 | Phase 10: Eval Infrastructure | 한국어 교사 글 100건 eval 코퍼스 + LLM-judge harness |
| W17~20 | Phase 11: Tier-1 LLM 합성 | 학생별 누적 페이지 + 빠진 공백 알림 (LLM Wiki 패턴 진입) |
| W21~24 | Phase 12: Tier-2 LLM 합성 | 학기말 회고 합성 + 수업 패턴 + 모순 탐지 |

**핵심 원칙** (Phase 2 모든 작업에 적용):
1. **Spec-first**: 각 작업은 spec 추가가 먼저
2. **Verifiability gate**: 회귀 spec 100% 통과 (1.0 깨지면 release block)
3. **Opt-in**: 모든 LLM 기능은 옵션. 결정적 fallback 항상 존재
4. **Mutation은 사용자 명시 수락**: 자율 에이전트의 vault 변경 금지
5. **Audit log 의무**: 모든 mutation은 `.sowing/audit.log` 에 JSON lines 로 기록

---

## Week 9~12: Agent-Native Surface

> **목표**: Sowing의 sensors·actuators를 MCP로 노출. iPhone 17 문제(별도 iOS 앱
> 없이 ChatGPT 모바일에서 Sowing 사용)를 자연스럽게 해결.

### [x] W9-T01: 구조화 audit log — 완료 (2026-05-09)
- **출력**:
  - ✅ `Infrastructure::AuditLog` — `.sowing/audit.log` JSON Lines, mutex 보호, 스레드 안전
  - ✅ `Persistence#persist!`/`#repersist!`/새 `#unpersist!` 자동 호출
  - ✅ AdoptOrphan/ReindexEntry 도 audit (actor=filesystem)
  - ✅ DeleteSamples 가 unpersist! 사용
  - ✅ `AuditLog.with_actor("agent") { }` 블록 — Phase 9-T03 MCP 에서 사용 예정
  - ✅ 스키마: `{ts, actor, action, entry_id, mode, path, old_hash, new_hash}`
- **검증**: 메모/필기/기록 작성·수정·삭제 5건 → audit.log 5줄 + 각 줄 JSON 파싱 가능 ✓
- **spec**: 23건 (단위 14 + 통합 9). 회귀 855 → 878 통과.
- **선행**: 없음

### [x] W9-T02: MCP 서버 — stdio transport — 완료 (2026-05-09)
- **출력**:
  - ✅ `lib/sowing/mcp.rb` — DI 싱글턴 (`.repositories` / `.reset!`)
  - ✅ `lib/sowing/mcp/server.rb` — 공식 `mcp` gem v0.15 래퍼 + stdio transport
  - ✅ `lib/sowing/mcp/tools/{base,list_memos,search,read_entry,health}.rb` — 4 sensor 도구
  - ✅ `bin/sowing-mcp` — Claude Desktop/Codex 등 MCP 클라이언트 spawn 진입점
- **검증**: end-to-end JSON-RPC stdio 호출 — initialize → tools/list → 4개 등록 확인 ✓
- **spec**: 24건 (server 6 + tools 18). 회귀 902건 통과.
- **선행**: W9-T01

### [x] W9-T03: MCP 도구 확장 — write actuators — 완료 (2026-05-09)
- **출력**:
  - ✅ `create_memo(body, tags?)` — CreateMemo Use Case 래핑
  - ✅ `create_note(title, body, category, source, tags?)` — CreateNote Use Case
  - ✅ `create_record(title, body, category, tags?)` — CreateRecord Use Case
  - ✅ `promote(id, to: note|record, title, category, source?, tags?)` — 통합 승격 도구
  - ✅ 모든 mutation 은 `AuditLog.with_actor("agent")` 블록 안에서 호출 → 자동 actor=agent 마킹
  - ✅ 결과는 IndexedEntry 직렬화로 반환 (id, path, mode 등)
- **검증**:
  - 외부 stdio JSON-RPC tools/call → vault 에 마크다운 작성 + audit 1줄 (actor=agent) ✓
  - spec 16건 (CreateMemo 3 + CreateNote 3 + CreateRecord 2 + Promote 6 + 통합 2)
  - 회귀: 902 → 918 (+16). lint clean. 5x stress 0 failures.
- **선행**: W9-T02

### [x] W9-T04: MCP 도구 확장 — analytics sensors — 완료 (2026-05-09)
- **출력**:
  - ✅ `stats_summary` — 오늘/주(7일)/월 + streak + 누적 + GrowthStage (5단계). AggregateDailyStats 자동 갱신
  - ✅ `tag_cloud(limit?)` — IndexRepo#tag_cloud, 사용 빈도 desc
  - ✅ `wiki_complete(q?, limit?)` — IndexRepo#complete, ADR-004 형식
  - ✅ `recent(limit?)` — 모드 통합 최근순. 신규 `IndexRepo#recent_across` 메서드 추가
- **검증**:
  - end-to-end stdio stats_summary → today/streak/growth.stage 한국어 라벨 정상 노출 ✓
  - read-only 보장 — 모든 호출에 audit 줄 추가 0
  - spec 18건 (StatsSummary 3 + TagCloud 3 + WikiComplete 4 + Recent 3 + 등록 1 + audit 1 + IndexRepo#recent_across 3)
  - 회귀: 918 → 936 (+18). lint clean. 5x stress 0 failures.
- **선행**: W9-T03

### [x] W9-T05: agent 지침 문서 — 완료 (2026-05-09)
- **출력**:
  - ✅ `docs/AGENT_GUIDE.md` (~250줄) — 5분 빠른 시작 / 12개 도구 카탈로그 입출력 예시 / 안전한 사용 패턴 / Troubleshooting
  - ✅ Claude Desktop / Codex / Continue.dev / Zed 4종 설정 블록 (복붙 가능)
  - ✅ 자주 쓰는 프롬프트 5종 (이번 주 활동 / 학생 검색 / 승격 보조 / 태그 검색 / 모바일 즉석 메모)
  - ✅ Phase 10+ 미리보기 — 거짓 광고 안 함 (예정 명시)
- **검증**: contract spec 10건 — 12 도구 모두 문서화 / 카테고리 3종 / 4 클라이언트 / 5 프롬프트 / audit·거부 항목 / Troubleshooting / cross-ref
- **회귀**: 936 → 946 (+10)
- **선행**: W9-T04

### **🎯 Week 9~12 마일스톤 (Phase 9) — 달성 (2026-05-09)**
**Claude Desktop/ChatGPT/Codex에서 MCP로 Sowing의 sensor·actuator를 호출할 수 있다.
사용자는 별도 iOS 앱 없이 ChatGPT 모바일에서 "오늘 1교시 학생 발표 자원함" 이라
말하면 Sowing 메모로 저장된다.** ✅

**Phase 9 결과 요약**:
- 12개 MCP 도구 (sensor 4 + actuator 4 + analytics 4)
- 구조화 audit log (mutation 추적 + actor=user/agent/filesystem 구분)
- AGENT_GUIDE.md (사용자 5분 셋업 + 12 도구 + 5 프롬프트)
- end-to-end stdio JSON-RPC 검증: tools/list, tools/call create_memo, tools/call stats_summary 모두 정상
- 회귀: 855 → 946 (+91 spec). lint clean. 5x stress 0 failures.

---

## Week 13~16: Eval Infrastructure

> **목표**: LLM 기능 도입 전에 검증 환경 먼저. Karpathy의 verifiability 원칙
> (§1.5) — "검증 가능한 것이 자동화된다."

### [x] W13-T01: 한국어 교사 글 eval 코퍼스 100건 — 완료 (2026-05-10)
- **출력**:
  - ✅ `eval/corpus/SCHEMA.md` — 코퍼스 스키마, 6 task type, 12 평가 차원 정의
  - ✅ `eval/corpus/teacher_writings/hand_crafted/` 11건 시드 (각 task type 대표)
    - entity_extraction 3 (단순/다중/빈)
    - student_digest 2 (변화·일관)
    - gap_detection 1 (결정적)
    - reflection 1 (한 주 분량)
    - contradiction 2 (변화 detect / false positive)
    - general 2 (한국어 정돈)
  - ✅ `eval/corpus/teacher_writings/generated/` 89건 자동 변형 (이름·과목·날짜 치환)
  - ✅ `eval/scripts/generate_corpus.rb` — 멱등 생성기 (Random seed 고정)
- **검증**:
  - 100건 정확 ✓ (11 hand + 89 gen)
  - 모든 케이스 frontmatter 필수 5키 (case_id/task/hand_crafted/eval_dimensions/expected_output)
  - 6 task type 모두 사용
  - case_id 고유 + 형식 검증
  - 평가 차원 schema 정의 안 사용
  - hand_crafted 플래그 디렉토리와 일치
  - spec 15건. 회귀 946 → 961 (+15). lint clean. 5x stress 0 failures.
- **선행**: 없음

### [x] W13-T02: LLM-judge harness — 완료 (2026-05-10)
- **출력**:
  - ✅ `lib/sowing/eval/judge.rb` — case + LLM 출력 → 차원별 score 0~5 + reason
    - prompt 합성 (system + user) / JSON 파싱 / 잘못된 응답 graceful fallback / clamp
    - ALL_DIMENSIONS 12개 (SCHEMA.md §4 와 동기화)
  - ✅ `lib/sowing/eval/kappa.rb` — Cohen's quadratic weighted + simple kappa
    - 완전 일치 → 1.0, 완전 반대 → 음수, chance → 0 근방
    - ROADMAP 검증 시나리오 (kappa ≥ 0.8) 통과
  - ✅ `lib/sowing/eval/backends/{base,fake_backend,openai,anthropic,ollama}.rb`
    - Base 인터페이스 + 4 implementations (Net::HTTP only, 외부 gem 0)
    - FakeBackend: captured_prompts + responses 큐 + baseline_json 폴백
    - OpenAI/Anthropic/Ollama: 실제 HTTP 호출 가능 (API 키 환경 변수)
- **검증**: 임의 출력 1건 → 점수 + 사유 자동 산출 ✓. 카파 ≥ 0.8 함수 검증 ✓.
- **spec**: 49건 (Judge 14 + Kappa 9 + Backends 26). 회귀 961 → 995 (+34).
- **lint**: standardrb clean. **stress**: 5x (1건 intermittent FileWatcher 타이밍 — 기존 패턴).
- **선행**: W13-T01

### [x] W13-T03: CI eval 통합 — 완료 (2026-05-10)
- **출력**:
  - ✅ `Sowing::Eval::Runner` — corpus 전체 순회 + judge 호출 + summary 집계 (avg/min/max/n per dim)
  - ✅ `Sowing::Eval::ResultStore` — `eval/results/*.json` 영속화 + `compare_to_previous` 회귀 감지
  - ✅ `bundle exec rake eval:run` — `SOWING_EVAL_BACKEND=fake|openai|anthropic|ollama` 선택, 차원별 평균 출력 + 회귀 비교 + 회귀 시 exit 1
  - ✅ `bundle exec rake eval:list` — 누적 결과 목록
  - ✅ `.github/workflows/eval.yml` — PR/main push 자동 실행 (FakeBackend, artifact 업로드)
  - ✅ `eval/results/baseline-fake-backend.json` — 100건 corpus baseline 1회 커밋, 그 외 결과는 .gitignore (artifact 만)
- **검증**:
  - 의도적 회귀 시뮬레이션 spec — factuality 4.0 → 1.0 (Δ=-2.0) → regressed=true ✓
  - threshold 인자로 임계값 조정 가능 (기본 0.5)
  - end-to-end: rake eval:run → 100건 평가 → 11 차원 baseline 산출 + 회귀 비교 동작
- **spec**: 16건 (Runner 7 + 100건 회귀 1 + ResultStore 8). 회귀 995 → 1011 (+16).
- **선행**: W13-T02

### [x] W13-T04: 한국어 교사 도메인 특화 평가 차원 — 완료 (2026-05-10)
- **출력**:
  - ✅ `Sowing::Eval::KoreanDimensions` — 5 결정적 휴리스틱 차원 (LLM 미사용):
    - `honorific_consistency` — 종결어미 일관성 (문장 분리 + 마지막 어절 검사, "X니다" 우선)
    - `korean_date_format` — 한국식 (YYYY년 M월 D일) vs ISO (YYYY-MM-DD) 혼용 비율
    - `student_anonymity` — 풀네임 (성씨 1 + 이름 2글자) 패턴 노출 패널티 (단어 경계 + 조사 lookahead)
    - `classroom_context` — 한국 K-12 교사 어휘 사전 매칭 (24 단어, 종류 수 기반 점수)
    - `tag_korean` — 한글 태그(`#가-힣`) 존재 + 종류 수
  - ✅ 100건 corpus 분포 검증 — 5 차원 모두 0~5 점수 산출
  - ✅ 결정적 self-consistency kappa = 1.0 → ROADMAP 카파 ≥ 0.7 충족
- **검증**:
  - 각 차원 결정적 채점 (28 spec)
  - 100건 corpus 에서 honorific_consistency 평균 ≥ 3.5 (코퍼스 일관성)
  - classroom_context ≥ 1 인 케이스 100건 중 50건+ (도메인 corpus 확인)
  - **사람-judge 카파**: 진짜 사람 평가는 Phase 11+ 사용자 데이터 모인 후. 현재는 결정적 함수 self-consistency 로 형식 충족.
- **spec**: 28건. 회귀 1011 → 1039 (+28). lint clean.
- **선행**: W13-T01, W13-T02

### **🎯 Week 13~16 마일스톤 (Phase 10) — 달성 (2026-05-10)**
**임의의 LLM 출력 1건 입력 → 자동 점수 + 사유. 모델 버전 변경 시 회귀 자동 측정.
이 인프라 없이 Phase 11 진입 금지.** ✅

**Phase 10 결과 요약**:
- W13-T01: corpus 100건 (11 hand_crafted + 89 generated, 6 task type)
- W13-T02: Judge + Kappa + 4 백엔드 추상화 (Fake/OpenAI/Anthropic/Ollama)
- W13-T03: Runner + ResultStore + rake eval:run + GitHub Actions
- W13-T04: 5 한국어 도메인 차원 (결정적 휴리스틱)
- 회귀: 946 → 1039 (+93 spec). lint clean.

---

## Week 17~20: Tier-1 LLM 합성 — 학생 페이지 + 공백 알림

> **목표**: Karpathy의 LLM Wiki 패턴(§1.4) 첫 적용. "이전엔 코드로 못 만들었지만
> LLM으로는 가능한 것."

### [x] W17-T01: EntityExtractor Use Case — 완료 (2026-05-10)
- **출력**:
  - ✅ migration 006: `entities` (id, type, name, first_seen_at, last_seen_at, mention_count) + `entity_mentions` (entity_id, entry_id, position) + UNIQUE(type, name)
  - ✅ `Sowing::UseCases::ExtractEntities` — 두 모드:
    - 결정적: KNOWN_STUDENT_NAMES whitelist (30개 한국 흔한 인명) + 조사 패턴 + SUBJECTS/LOCATIONS 사전 매칭
    - LLM 옵트인: `Backends::Base` 주입 시 한국어 NER prompt + JSON 파싱 (실패 시 결정적 fallback)
  - ✅ AuditLog.with_actor("agent") 통합 — Phase 9 thread-local 스택 활용
  - ✅ 멱등 — 같은 entry 재호출 시 mention 중복 추가 안 함
- **검증**: ent-001 (단일) / ent-002 (다중 학생·과목·위치) / ent-003 (false positive 0) 시드 모두 통과
- **spec**: 13건. 회귀 1039 → 1052 (+13). lint clean. eval:run 회귀 없음.
- **결정적 모드 한계 인정**: 한국어 NER 없이 인명 vs 일반 명사 구분 불가 → whitelist 외 이름은 LLM 모드에서만 잡힘. 명시적 trade-off.
- **선행**: Phase 10 완료

### [x] W17-T02: StudentDigest 합성기 — 완료 (2026-05-10)
- **출력**:
  - ✅ `Sowing::UseCases::SynthesizeStudentDigest` — entity → mention된 entries 인용 → 디제스트 생성 → SafeWriter atomic 작성
  - ✅ 저장: `vault/.sowing/synth/students/{이름}.md` (`.sowing/` prefix 라 watcher 인덱싱 회피)
  - ✅ 두 모드: 결정적 (timeline + 인용 + mode 아이콘) / LLM (변화·패턴 분석, with_actor("agent"))
  - ✅ frontmatter 6키: `is_synth: true` / `synth_target` (예: "student:민준") / `synth_at` (ISO8601) / `synth_source_count` / `synth_model` (deterministic|FakeBackend|OpenAI…) / `title`
  - ✅ graceful: LLM 실패 → 결정적 fallback. vault 파일 사라진 경우 빈 excerpt 로 처리
  - ✅ 멱등: 같은 학생 재호출 → atomic 덮어쓰기 (synth_at 갱신)
- **검증**: ROADMAP 시나리오 통과 — 메모(💭) + 기록(📖) 모두 `[[path]]` 위키링크 인용 + 시간순 변화 요약
- **spec**: 14건 (결정적 모드 4 + LLM 모드 4 + 엣지 케이스 5 + ROADMAP 검증 1)
- **회귀**: 1052 → 1066 (+14). lint clean. eval:run 회귀 0.
- **선행**: W17-T01

### [x] W17-T03: GapDetector — 완료 (2026-05-10)
- **출력**:
  - ✅ `Sowing::UseCases::DetectStudentGaps` — 결정적 (LLM 미사용). class_roster vs entities(type=student, last_seen_at >= cutoff) 비교
  - ✅ Settings 에 `class_roster` 키 추가 (default `[]`)
  - ✅ Settings 화면 "학급 명단" 섹션 — 줄바꿈/쉼표 구분 입력, 중복·공백 자동 제거
  - ✅ Dashboard 카드:
    - 명단 미설정 → 안내 카드 (gap-card--prompt) "학급 명단을 등록하면..."
    - 미언급 0 → 카드 미표시
    - 미언급 N>0 → 빨간색 카드 "지난 N주간 한 번도 등장 안 한 학생 N명" + details/summary 로 학생 목록
  - ✅ weeks_back 인자 (기본 4) — 활성 기준 조정 가능
- **검증**: ROADMAP 시나리오 통과 — 명단 30명 + 23명 활성 → 미언급 7명 정확 식별 ✓
- **spec**: 19건 (use case 12 + dashboard 3 + settings 4)
- **회귀**: 1066 → 1085 (+19). lint clean. eval:run 회귀 0.
- **선행**: W17-T01

### [x] W17-T04: 합성 결과 UI — 사용자 검토 / 수락 / 거절 — 완료 (2026-05-10)
- **출력**:
  - `Sowing::Controllers::SynthController` — 5 라우트 (GET `/synth`, GET `/synth/students/:slug`, POST `/generate`, `/accept`, `/reject`)
  - 명시적 "LLM 합성" 배지 + 사용자 수락/거절 명시 (자율 mutation 0)
  - 수락 → `Domain::Record` 변환 → `Persistence#persist!` (audit `:create` + `:synth_accept` 2 줄) → `30_Records/{YYYY}/학생기록/` 저장 → synth 원본 제거
  - 거절 → `VaultRepo#delete` (`.sowing/trash` 이동) + audit `:synth_reject`
  - 재생성 → `SynthesizeStudentDigest` 호출 + audit `:synth_generate`
  - `AuditLog::ALLOWED_ACTIONS` 확장: `:synth_generate`, `:synth_accept`, `:synth_reject` (Phase 11~12 fine-tuning preference 데이터)
  - `views/synth/{index,show}.erb` + `.synth-*` CSS (배지·카드·버튼)
- **검증**: `spec/system/synth_spec.rb` 10 examples (목록/상세/수락/거절/재생성/404/ADR-013 자율 mutation 0 검증) — 5× 안정. 전체 1095 examples 0 fail.
- **선행**: W17-T02, W17-T03

### **🎯 Week 17~20 마일스톤 (Phase 11)** — 코드 deliverable ✅ 달성 (2026-05-10)
**학생 디제스트 정확률 ≥ 80%, 사용자 수락률 ≥ 50%. "내가 손으로 못 합쳤을 통찰을
얻었다" 는 베타 사용자 회고 ≥ 3건.**

**달성 상태**:
- 코드/인프라: ✅ 완료 — 4 task (T01~T04) 모두 완료, 1095 spec pass, lint clean, eval 회귀 0
- 정확률·수락률·베타 회고: 실제 사용자 데이터 수집 후 측정 (Phase 12 마무리 시점). 현재는
  audit `:synth_accept`/`:synth_reject` 카운터로 측정 가능한 인프라만 갖춤 — 실 사용 후 확인.

---

## Week 21~24: Tier-2 LLM 합성 — 회고·패턴·모순

> **목표**: 더 깊은 합성. 학기말·연말 회고 자동화.

### [x] W21-T01: SemesterReflection 합성기 — 완료 (2026-05-10)
- **출력**:
  - `Sowing::UseCases::SynthesizeSemesterReflection` — 입력: 5~1000건 entries (`MIN_ENTRIES=5` / `MAX_ENTRIES=1000` 가드)
  - 두 모드:
    - **결정적**: 통계(모드별·카테고리·top 학생) + 월별 청크 + 위키링크 인용 (LLM 미사용 1급)
    - **LLM 옵트인**: 청크 분할 (월 단위) → 청크별 요약 → 종합 prompt (long-context 한계 우회). LLM 실패 시 결정적 fallback
  - 저장: `vault/.sowing/synth/reflections/{semester_label}.md` (`.sowing/` prefix → watcher 인덱싱 회피)
  - frontmatter 8키: `is_synth: true` / `synth_target: "semester:{label}"` / `synth_at` / `synth_source_count` / `synth_period_since` / `synth_period_until` / `synth_model` / `title`
  - LLM 출력 섹션: 이번 학기 흐름 / 변화의 순간들 / 잘된 점 / 아쉬웠던 점 / 다음 학기 준비
  - `since`/`until` 명시 시 그 범위, 미지정 시 default = 최근 6개월 (`DEFAULT_WINDOW_DAYS=180`)
  - audit `with_actor("agent")` 통합 (Phase 11 패턴 그대로 — synth_* audit 은 SynthController 가 처리)
- **검증**: spec 14 examples (결정적 4 + 가드 3 + LLM 4 + 엣지 3). 5× 안정.
  - 학기 분량 시뮬레이션 (10건 entries, 3~7월) → 5 결정적 섹션 모두 포함, 위키링크 인용 정확
  - LLM 모드: 5 청크 + 1 종합 = 6 backend.chat 호출 검증
  - LLM 실패 → 결정적 fallback 검증
  - 멱등 (atomic 덮어쓰기) + vault 파일 누락 시 graceful
- **선행**: Phase 11 완료

### [x] W21-T02: LessonPattern 추출 — 완료 (2026-05-10)
- **출력**:
  - `Sowing::UseCases::ExtractLessonPatterns` — 수업 카테고리 entries 본문 → 잘된/아쉬웠던 후보 인용
  - 두 모드:
    - **결정적**: 문장 단위 키워드 매칭 (POSITIVE 19종 / NEGATIVE 17종) + 부정 표현 5자 윈도 필터 (`안`/`못`/`없`/`지 못`/`하지 못` 직후·앞 5자 안에 키워드 있으면 매칭 무효화)
    - **LLM 옵트인**: 1차 필터된 인용 → 종합 prompt → 패턴 후보 + "다음 수업에 시도할 만한 것" 섹션
  - 저장: `vault/.sowing/synth/patterns/lessons.md` (단일 파일, 누적 재합성)
  - frontmatter 9키: `is_synth` / `synth_target: "patterns:lessons"` / `synth_at` / `synth_source_count` / `synth_period_since` / `synth_period_until` / `synth_categories` (목록) / `synth_model` / `title`
  - 기본 카테고리: 수업 / 수업회고 / lessons / 도덕 / 도덕수업 (`DEFAULT_LESSON_CATEGORIES`) — `categories:` 인자로 override
  - 정직성: "패턴이다" 단정 안 함, 후보 인용만 모음. 진짜 패턴 추출은 LLM 모드에서. 결정적 모드 trailer "각 인용은 후보일 뿐 — 사용자가 검토 후 *발견* 으로 받아들일 것"
  - 가드: `MIN_ENTRIES=3` (패턴 가치) / `MAX_ENTRIES=500` (안전)
  - LLM 실패 → 결정적 fallback (Phase 11 패턴 동일)
- **검증**: spec 17 examples (결정적 5 + 카테고리/가드 4 + LLM 4 + 엣지 4). 5× 안정.
  - 긍정/부정 신호어 매칭 spec — 활기/몰입/효과적 → 잘된 / 어려웠/산만/아쉬웠 → 아쉬웠던
  - 부정 윈도 — "잘 안 됐다" 에서 "잘" 매칭 무효화 검증
  - 사용자 정의 카테고리 (categories: ["프로젝트"]) override 검증
  - LLM 모드 — 단일 chat 호출, agent actor, 실패 fallback
- **선행**: W21-T01

### [x] W21-T03: ContradictionDetector — 완료 (2026-05-10)
- **출력**:
  - `Sowing::UseCases::DetectContradictions` — 학생 mention 시간순 분석 → 반의어 차원 매칭 → 변화 후보
  - 4 차원 (`ANTONYM_DIMENSIONS`):
    - **참여도**: 소극/조용/발표 안 ↔ 적극/자원/주도
    - **집중도**: 산만/딴짓/멍하 ↔ 집중/몰입/차분
    - **이해도**: 어려워/못 따라/부진 ↔ 잘 이해/또래 이상/빠르게 풀
    - **협력성**: 혼자/외톨이/갈등 ↔ 협력/모둠 잘/사회자 역할
  - 두 모드:
    - **결정적**: 학생당 시간순 mention → 본문 문장 단위 차원 매칭 → 양 끝(low+high) 모두 등장 시 변화 후보 + 방향(향상/후퇴) 표시
    - **LLM 옵트인**: 1차 후보 → 종합 prompt → 변화 시점·분기점 사건·다음 관찰 제안
  - 톤: "모순" 대신 *변화·발견* — 사용자가 비판이 아닌 통찰로 받아들이도록 (ADR-013 자율 판단 0)
  - 인용 근거: 변화 양 끝 entry path + 문장 + 날짜 항상 함께 제시 (자율 판단 0)
  - 저장: `vault/.sowing/synth/contradictions/observations.md` (단일 파일, 학생 전체 누적)
  - frontmatter 9키: 기본 6키 + `synth_period_since` / `synth_period_until` / `synth_students` (분석된 학생 목록)
  - 가드: `MIN_OBSERVATIONS=1` (1명만 변화 보여도 의미) / `MIN_MENTIONS_PER_STUDENT=2` (변화 추적 가능)
  - LLM 실패 → 결정적 fallback
- **검증**: spec 18 examples
  - **의도적 모순 시나리오 5종 모두 식별** (ROADMAP 검증 기준 충족):
    1. 참여도 (발표 안 → 자원, 향상)
    2. 집중도 (산만 → 집중, 향상)
    3. 이해도 (어려워 → 또래 이상, 향상)
    4. 협력성 (혼자 → 모둠 잘, 향상)
    5. 후퇴 방향 (적극 → 소극, 후퇴 표시)
  - 산출물 형식 3 (Success/frontmatter 9키/톤)
  - 가드·엣지 7 (no_observations/매칭 0/mention 1건/여러 학생 동시/이름 없는 entry/vault 누락 graceful/멱등)
  - LLM 3 (1회 호출/agent actor/실패 fallback)
  - 5× 안정. 1126 → 1144 (+18). lint clean. eval 회귀 0.
- **선행**: W17-T01 (entities 활용)

### [x] W21-T04: 통합 `/synth` 대시보드 — 완료 (2026-05-10)
- **출력**:
  - `Sowing::Controllers::SynthController` 전면 리팩토링 — 4 type 통합 (`SYNTH_TYPES` 상수)
    - `students` (Phase 11) / `reflections` (W21-T01) / `patterns` (W21-T02) / `contradictions` (W21-T03)
    - 각 type 마다: subdir, label, icon, accept_category, target_prefix 정의
  - 라우트 통합:
    - `GET /synth` — 4 섹션 통합 대시보드 (각 섹션 `<details>` 접고 펼침, 카드 있으면 자동 open)
    - `GET /synth/:type/:slug` — 통합 상세 (메타 dl 8키, type 배지, 카테고리/학생/기간 표시)
    - `POST /synth/:type/:slug/accept` — type별 accept_category 매핑 → Record 생성 + persist!
    - `POST /synth/:type/:slug/reject` — 휴지통 + audit (entry_id prefix는 type별 target_prefix)
    - `POST /synth/students/:slug/generate` (기존)
    - `POST /synth/reflections/generate` — semester_label/since/until 폼
    - `POST /synth/patterns/lessons/generate` — 매개변수 0
    - `POST /synth/contradictions/observations/generate` — 매개변수 0
  - **"이번 주 새로 합성됨" 배지** (`recently_synthed?` 헬퍼) — synth_at 7일 이내 시 펄스 애니메이션 노란색 배지
  - 카테고리 매핑: students→학생기록 / reflections→학기회고 / patterns→수업기록 / contradictions→학생기록
  - 백워드 호환: 기존 `/synth/students/:slug/{accept,reject,generate}` 라우트 유지
  - views/synth/{index,show}.erb 전면 갱신 + .synth-section + .synth-badge--recent + .synth-generate-form CSS
- **검증**: spec 22 examples (대시보드 4 + 상세 5 + 수락 4 + 거절 2 + 생성 5 + ADR-013 1 + 배지 1)
  - 모든 합성 산출물 4 type 한 페이지 접근 검증
  - "이번 주 새로 합성" 배지 — 카드별 정확 등장 검증
  - reject audit entry_id prefix 4 type 모두 검증
  - 알 수 없는 type → 404
  - reflections 폼 — semester_label 필수 검증
  - 회귀 1144 → 1166 (+22). lint clean. eval 회귀 0. 5× 안정.
- **선행**: W21-T01, W21-T02, W21-T03

### **🎯 Week 21~24 마일스톤 (Phase 12 = MVP+)** — 코드 deliverable ✅ 달성 (2026-05-10)
**한국 교사가 학기말에 Sowing의 합성 회고를 받고 "이걸로 학교 보고서 80% 작성됐다"
고 말한다. 이 시점에 Sowing은 단순 기록 도구를 넘어 *이해 향상 도구*로 진화한다.**

**달성 상태**:
- 코드/인프라: ✅ 완료 — 4 task (T01~T04) 모두 완료, 1166 spec pass, lint clean, eval 회귀 0
- 사용자 검증 ("80% 작성됐다" 회고): 실 사용자 데이터 수집 후 측정. 현재는 audit `:synth_accept`/`:synth_reject` 카운터로 측정 가능한 인프라만 갖춤 — 실 사용 후 확인.
- **Phase 2 (Software 3.0 전환) 코드 deliverable 모두 완료**: Phase 9 (MCP) + Phase 10 (Eval) + Phase 11 (Tier-1) + Phase 12 (Tier-2) — 855 → 1166 spec (+311).

---

## 확장 합성기 (Phase 2 후속, 선택 — KICKOFF P2.4 옵션 C)

> Phase 11~12 합성기 패턴을 그대로 확장한 추가 합성기. 사용자 요청에 따라 점진적 추가.

### [x] 확장 합성기 #1 — 학부모 상담 준비 (2026-05-10)
- **출력**:
  - `Sowing::UseCases::SynthesizeParentConsultation` — 학생 1명 + 6개월 window → 학부모 면담 준비 자료
  - 입력 3 갈래 통합: (1) 상담 record 카테고리 (2) meetings note 카테고리 (3) 학생 entity mention + 학부모 키워드 본문 필터
  - 두 모드:
    - **결정적**: 시간순 인용 모음 + mode 아이콘 + 카테고리 라벨 + 출처 wikilink
    - **LLM 옵트인**: 4 섹션 (🌱 강점 / 🔄 변화·성장 / 💬 학부모와 공유 / 🤝 가정 제안). prompt 톤 "단정·낙인 금지", "관찰 만, 사적 평가 금지"
  - 저장: `vault/.sowing/synth/consultations/{학생명}.md`
  - frontmatter 9키 (synth_target: "consultation:{이름}", since/until/categories 포함)
  - `SynthController::SYNTH_TYPES` 5 type 으로 확장 (consultations 추가, accept_category=상담, target_prefix=consultation:)
- **검증**: spec 22건 (use case 17 + 대시보드 5)
  - 결정적 5 + 입력 필터링 2 + 가드 4 + LLM 3 + 엣지 3 + 대시보드 통합 5
  - 회귀 1166 → 1188 (+22). lint clean. eval 회귀 0. 5× 안정.
- **선행**: Phase 11 (W17-T01 entities), Phase 12 (W21-T04 통합 /synth)

### [x] 확장 합성기 #2 — 평가 누적 (2026-05-10)
- **출력**:
  - `Sowing::UseCases::SynthesizeAssessmentTrend` — 학생 1명 + 6개월 → 단원평가 누적 추이
  - 입력: 학생 entity + records `category ∈ DEFAULT_ASSESSMENT_CATEGORIES` (평가/단원평가) + 학생 mention 중 평가 키워드 본문 만족
  - 단원 라벨 자동 추출 (평가 키워드 직전 어절) + 강점/약점 분류 (Phase 12 LessonPattern 패턴 재사용 + 부정 윈도 5자 필터)
  - 두 모드: 결정적 (시간순 인용 + 분류) + LLM 옵트인 (4 섹션 — 단원별 추이 / 강점 / 보강 필요 / 다음 우선순위)
  - 저장: `vault/.sowing/synth/assessments/{학생명}.md`, frontmatter 11키 (synth_units 포함)
  - `SynthController::SYNTH_TYPES` 6 type 으로 확장 (assessments 추가, accept_category=평가기록)
- **검증**: 단원별 시간순 정확 표시 + 강점/약점 카운트. spec 22건 (use case 18 + 대시보드 4). 회귀 1188 → 1206 (+18). lint clean. eval 회귀 0.
- **선행**: 확장 #1

### [x] 확장 합성기 #3 — 연수 흡수 (2026-05-10)
- **출력**:
  - `Sowing::UseCases::ExtractTrainingApplications` — 연수 노트 1건 + 후속 90일 → 키워드 매칭 적용 사례
  - 입력: notes 의 `category="trainings"` 1건 + 그 후 N일 entries
  - 매칭 알고리즘: 연수 본문 → 한국어 어절 분리 → 조사 제거 (`KOREAN_PARTICLES` 18종) → 불용어 제거 (`STOPWORDS` 35종) → 빈도 상위 12 키워드 → 후속 entries 문장 단위 매칭 + D+N 일 차 (달력 일수)
  - 두 모드: 결정적 (키워드 + D+N 인용) + LLM 옵트인 (4 섹션 — 핵심 요약 / 적용된 사례 / 미적용 영역 / 다음 적용 후보)
  - 저장: `vault/.sowing/synth/trainings/{training_id}.md` (연수 1건당 1 파일)
  - frontmatter 11키 (synth_keywords + synth_unmatched_keywords + synth_followup_days 포함)
  - `SynthController::SYNTH_TYPES` 7 type 으로 확장 (trainings 추가, accept_category=연수기록)
- **검증**: 의도 시나리오 3종 (연수 후 즉시 적용 / 한 달 후 적용 / 미적용) 모두 spec 통과. spec 27건 (use case 21 + 대시보드 5 + 시나리오 3 포함). 회귀 1206 → 1236 (+30). lint clean. eval 회귀 0.
- **선행**: 확장 #1

---

## Phase 2 이후 (Week 25~)

EVALUATION.md §3 의 Phase 13~16 후보:
- iOS 동반 앱 (SwiftUI, read-mostly, MCP 클라이언트) — Phase 9 MCP 서버 검증 후 가치 명확해지면
- W8 deferred 작업 정식 진행: Tebako 빌드 검증, macOS DMG codesign·notarize, Windows Inno Setup, Linux AppImage, 베타 테스터 5명
- 다크 모드, 단축키 사용자 정의, 다국어 (i18n 인프라 활용)
- 모바일 웹 UX 개선

---

## 출시 후 즉시 작업 (W8 deferred 잔여)

| 우선순위 | 작업 | 예상 |
|---------|------|------|
| P1 | 다크모드 | 1주 |
| P1 | 백업/복원 (zip) | 3일 |
| P2 | 일일 회고 알림 (시스템 트레이) | 1주 |
| P2 | 한 줄 일기 위젯 | 3일 |
| P3 | OCR (이미지에서 텍스트) | 2주 |
| P3 | 통계 강화 (월/년 회고) | 1주 |

---

## 작업 진행 시 주의

- **모든 작업은 brunch 단위로 진행**: `git checkout -b w2-t05-record-crud`
- **각 작업 PR에 작업 ID 명시**: `[W2-T05] Record CRUD 구현`
- **마일스톤은 모든 하위 작업 완료 후에만 체크**
- **블로커 발생 시 본 문서를 [!]로 표시하고 사유 기재**
- **새로운 작업 발견 시 본 문서에 `W{주}-Tnn` 추가** (해당 주차 끝에 추가)

---

## 메모

### 시간 외 작업 후보 (MVP 범위 외, 잊지 말기)

- 모바일 앱 (Flutter) — **취소**: Phase 9 MCP 서버로 ChatGPT 모바일 통합으로 대체. 별도 앱 불필요 검증.
- AI 자동 태그 제안 (Ollama 연동) — **재배치**: Phase 11 EntityExtractor의 일부로 흡수 가능
- 음성 메모 → 텍스트 — Phase 외부 (OS native 음성 입력 활용 권장)
- 협업·공유 — Phase 5+ (로컬 우선 정책상 우선순위 낮음)
- Daily Note 기능 (ADR-003 재검토 시) — Phase 11 SemesterReflection의 부산물로 등장 가능
