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

### [ ] W2-T01: Sinatra 라우트·뷰 구조 정립
- **출력**:
  - `lib/sowing/controllers/application_controller.rb` (Sinatra::Base)
  - `lib/sowing/controllers/dashboard_controller.rb`
  - `views/layouts/application.erb` — Hotwire 로딩, 한국어 metadata
  - `views/dashboard/show.erb` — 빈 대시보드
  - `public/css/application.css` — 디자인 토큰 (SPEC §10.4)
- **검증**: 브라우저에서 한국어 대시보드 표시
- **선행**: W1 전체

### [ ] W2-T02: 글로벌 단축키 + 빠른 메모 모달
- **출력**:
  - `views/memos/_quick_modal.erb`
  - `public/js/controllers/quick_memo_controller.js` (Stimulus)
  - `MemosController#create` — Turbo Stream 응답
- **검증**:
  - `Cmd/Ctrl+Shift+M` 으로 모달 호출
  - 입력 후 `Cmd/Ctrl+Enter` 로 저장, 자동 닫힘
  - 대시보드에 즉시 반영 (Turbo Stream)
- **선행**: W2-T01, W1-T08

### [ ] W2-T03: 메모 목록 화면
- **출력**:
  - `MemosController#index`
  - `views/memos/index.erb`
  - 페이지네이션 또는 무한스크롤
- **검증**: 100건 이상에서도 < 200ms 응답
- **선행**: W2-T01

### [ ] W2-T04: 필기(Note) CRUD
- **출력**:
  - `lib/sowing/use_cases/create_note.rb`, `update_note.rb`
  - `NotesController` (index, new, create, edit, update, show)
  - `views/notes/*` (form, show, index)
  - 카테고리 select (수업/연수/도서/회의)
  - 출처 필드 필수 검증
- **검증**: CRUD 전체 흐름 + 카테고리 필터 동작
- **선행**: W2-T01

### [ ] W2-T05: 기록(Record) CRUD
- **출력**: 위와 동일한 구조로 RecordsController
- **검증**: CRUD 전체 흐름
- **선행**: W2-T01

### [ ] W2-T06: 마크다운 에디터 통합 (CodeMirror 6)
- **출력**:
  - `public/js/controllers/editor_controller.js`
  - CDN 로드 + Markdown 모드
  - `views/shared/_editor.erb` 부분뷰
- **검증**: 필기·기록 작성 시 CodeMirror 표시, 저장 시 텍스트 정상 전송
- **선행**: W2-T04, W2-T05

### [ ] W2-T07: 마크다운 실시간 프리뷰
- **출력**:
  - 좌측 에디터 / 우측 프리뷰 분할 뷰
  - 서버측 Commonmarker 렌더 + Turbo Stream으로 디바운스 갱신 (300ms)
- **검증**: 입력 후 300ms 이내에 프리뷰 갱신
- **선행**: W2-T06

### **🎯 Week 2 마일스톤**
**브라우저에서 빠른 메모 모달과 필기·기록 작성 화면이 동작한다.**

---

## Week 3: 승격 + 위키링크 + 태그

### [ ] W3-T01: 위키링크 파서·렌더러
- **출력**:
  - `lib/sowing/infrastructure/markdown/wiki_link.rb`
  - 본문에서 `[[link]]`, `[[link|alias]]` 추출
  - 옵시디언 호환 escape 처리
  - spec 포함 (옵시디언 호환성 케이스)
- **검증**: spec/compatibility 의 wiki link 케이스 통과
- **선행**: W2 전체

### [ ] W3-T02: 위키링크 그래프 인덱스
- **출력**:
  - `db/migrations/002_create_links.rb`
  - `IndexRepo#upsert_links(entry_id, [...])`
  - 깨진 링크 추적
- **검증**: 링크 추가·제거 시 그래프 갱신
- **선행**: W3-T01

### [ ] W3-T03: 위키링크 자동완성 API
- **출력**:
  - `GET /api/wiki_complete?q=` 엔드포인트
  - 메모/필기/기록 모두 후보에 포함 (ADR-004)
  - 정렬: 모드 우선순위 (record > note > memo) + 최근순
- **검증**: 응답 < 100ms (10,000건 기준), 결과 형식이 ADR-004 명세 준수
- **선행**: W3-T02

### [ ] W3-T04: CodeMirror 위키링크 자동완성
- **출력**:
  - `public/js/controllers/editor_controller.js` 확장
  - `[[` 입력 시 200ms 디바운스 후 자동완성 팝업
- **검증**: UX 시나리오 통과 (입력 → 후보 → Tab으로 선택 → 닫힘)
- **선행**: W3-T03

### [ ] W3-T05: 태그 시스템
- **출력**:
  - `db/migrations/003_create_tags.rb`
  - 본문 `#태그` + frontmatter `tags` 양쪽 추출
  - `TagsController#index` — 태그별 항목 목록
  - 태그 자동완성
- **검증**: 모든 곳에서 태그 검색·필터 동작
- **선행**: W2 전체

### [ ] W3-T06: 메모 → 필기 승격
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

### [ ] W3-T07: 필기·메모 → 기록 승격
- **출력**: W3-T06 패턴으로 `promote_to_record.rb`
- **검증**: 동일
- **선행**: W3-T06

### **🎯 Week 3 마일스톤**
**메모 → 필기 → 기록 승격 흐름과 위키링크 자동완성이 완전 동작한다.**

---

## Week 4: 검색 + 한국어 처리

### [ ] W4-T01: SQLite FTS5 가상 테이블
- **출력**:
  - `db/migrations/004_create_entries_fts.rb` — trigram 토크나이저 사용
  - `IndexRepo#index_for_search`, `search_full_text`
  - 인덱스 자동 동기화 트리거
- **검증**: 기본 검색 동작, 인덱스 누락 없음
- **선행**: W3 전체

### [ ] W4-T02: 한국어 검색 폴백 (LIKE)
- **출력**:
  - 한글 비율 ≥ 30% 쿼리는 LIKE 폴백
  - 5,000건 기준 < 500ms 보장
- **검증**: 한국어 부분일치 검색 정확도 확인 (테스트 픽스처)
- **선행**: W4-T01

### [ ] W4-T03: 검색 화면
- **출력**:
  - `SearchController#index`
  - `views/search/index.erb` — 검색창, 필터, 결과
  - 필터: 모드, 태그, 카테고리, 날짜 범위
- **검증**: 모든 필터 조합 동작
- **선행**: W4-T02

### [ ] W4-T04: 통합 검색 단축키
- **출력**:
  - `Cmd/Ctrl+K` 글로벌 검색 모달
  - 검색 결과 클릭 시 해당 entry로 이동
- **검증**: 어디서든 단축키로 검색 가능
- **선행**: W4-T03

### **🎯 Week 4 마일스톤**
**5,000건 데이터에서 한국어 검색이 < 500ms로 동작한다.**

---

## Week 5: 동기화 + 옵시디언 통합

### [ ] W5-T01: 파일시스템 감시 (Listen gem)
- **출력**:
  - `lib/sowing/infrastructure/filesystem/file_watcher.rb`
  - 500ms debounce, 자체 쓰기 무시(self-write filter)
  - 백그라운드 스레드 또는 async fiber
- **검증**: 외부 에디터로 파일 수정 시 감지 확인
- **선행**: W1-T06

### [ ] W5-T02: 외부 변경 → 인덱스 갱신
- **출력**:
  - 변경 이벤트 → `ReindexEntry` Use Case 호출
  - mtime/hash 비교로 실제 변경만 처리
  - Turbo Stream으로 클라이언트 푸시 (SSE 또는 ActionCable 대안)
- **검증**: 옵시디언으로 편집한 내용이 본 앱에 자동 반영
- **선행**: W5-T01

### [ ] W5-T03: 외부 신규 파일 자동 입양 (Adoption)
- **출력**:
  - frontmatter 없는 파일 발견 시 자동으로 ULID·mode 부여
  - 사용자 설정으로 자동/수동 선택
- **검증**: 옵시디언에서 새 파일 만들고 본 앱에서 인식되는지 확인
- **선행**: W5-T02

### [ ] W5-T04: 부팅 시 일관성 검증
- **출력**:
  - 앱 시작 시 볼트 스캔 + SQLite 비교
  - 차이 발견 시 자동 동기화 또는 사용자 확인
- **검증**: 인덱스 삭제 후 부팅 → 자동 재구축
- **선행**: W5-T02

### [ ] W5-T05: 충돌 처리 다이얼로그
- **출력**:
  - 동시 편집 감지 시 modal: Keep Mine / Keep Theirs / Compare
  - 사용자 선택에 따라 적용
- **검증**: 의도적 충돌 시나리오 통과
- **선행**: W5-T02

### **🎯 Week 5 마일스톤**
**본 앱과 옵시디언을 동시에 켜고 양방향 편집이 안정적으로 동기화된다.**

---

## Week 6: 대시보드 + 통계 + 템플릿

### [ ] W6-T01: 통계 집계
- **출력**:
  - `db/migrations/005_create_daily_stats.rb`
  - `lib/sowing/use_cases/aggregate_daily_stats.rb` — 야간 또는 부팅 시 실행
  - streak 계산
- **검증**: 7일 연속 작성 시 streak = 7
- **선행**: W3 전체

### [ ] W6-T02: 대시보드 위젯
- **출력**:
  - 오늘/이번주/이번달 카운트
  - streak 표시
  - 최근 메모 5건
- **검증**: 모든 숫자 정확
- **선행**: W6-T01

### [ ] W6-T03: 씨앗-숲 시각화
- **출력**:
  - SVG 기반 시각화 (외부 라이브러리 없이)
  - 누적 기록 수에 따라 씨앗/새싹/나무/숲 단계 변화
- **검증**: 디자인 합의 후 시각적 검증
- **선행**: W6-T01

### [ ] W6-T04: 템플릿 시스템
- **출력**:
  - `lib/sowing/repositories/template_repo.rb`
  - 템플릿 적용 시 Liquid/ERB 단순 치환
  - 사용자 정의 템플릿 추가 UI
- **검증**: 템플릿으로 작성 시 placeholder가 올바르게 채워짐
- **선행**: W2 전체

### [ ] W6-T05: 12종 교사 템플릿 작성
- **출력**: SPEC §4.1 F8 의 12종을 `templates/` 에 마크다운으로
- **검증**: 모든 템플릿이 옵시디언으로 정상 표시
- **선행**: W6-T04

### **🎯 Week 6 마일스톤**
**대시보드, 시각화, 12종 템플릿이 모두 동작한다.**

---

## Week 7: 온보딩 + 샘플 콘텐츠 + 동기화 가이드

### [ ] W7-T01: 첫 실행 마법사
- **출력**:
  - `OnboardingController` — 단계별 화면
  - 볼트 위치 선택, 사용자 프로필, 샘플 동의
  - 단계별 진행 표시
- **검증**: 신규 사용자가 5분 이내 완료
- **선행**: W6 전체

### [ ] W7-T02: 12종 샘플 콘텐츠 작성 (ADR-005)
- **출력**:
  - `templates/samples/` 에 12개 마크다운 파일
  - 메모 4 + 필기 4 + 기록 4
  - 모두 `is_sample: true` frontmatter
- **검증**: 옵시디언 호환, 위키링크 일부 포함하여 그래프 시연 가능
- **선행**: W6-T05

### [ ] W7-T03: 샘플 콘텐츠 시드 명령
- **출력**:
  - `lib/sowing/use_cases/seed_samples.rb`
  - `bundle exec rake vault:seed`
  - 온보딩에서 호출
- **검증**: 동의 시에만 실행, 중복 시드 방지
- **선행**: W7-T02

### [ ] W7-T04: 첫 메모 인터랙티브 튜토리얼
- **출력**: 3분짜리 인터랙티브 가이드
  - 빠른 메모 → 저장 → 필기 승격 → 기록 승격
- **검증**: 전체 흐름 완료
- **선행**: W7-T01

### [ ] W7-T05: 클라우드 동기화 가이드 4종 (ADR-006)
- **출력**:
  - `templates/guides/sync_*.md` 4개 (iCloud, OneDrive, Dropbox, Syncthing)
  - 설정 화면에서 표시
- **검증**: OS별 매트릭스 정확, 링크 유효
- **선행**: W6 전체

### [ ] W7-T06: 설정 화면
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

### [ ] W8-T01: 시스템 트레이 wrapper (선택, OS별)
- **출력**:
  - macOS: 메뉴바 앱 (Swift 또는 platypus 활용)
  - Windows: 시스템 트레이 (별도 wrapper)
  - 메뉴: 빠른 메모, 대시보드 열기, 종료
- **검증**: 메뉴바에서 단축 액션 동작
- **선행**: W5 전체

### [ ] W8-T02: Tebako 빌드 검증
- **출력**:
  - `packaging/tebako.yml`
  - macOS·Linux 빌드 스크립트
  - 빌드 결과물 동작 확인
- **검증**: Tebako로 빌드한 단일 파일이 정상 실행
- **선행**: W7 전체

### [ ] W8-T03: macOS DMG + codesign + notarize
- **출력**:
  - `packaging/macos/build.sh`
  - DMG 생성, Apple 서명, notarize 자동화
- **검증**: 외부 사용자가 다운로드해도 Gatekeeper 경고 없음
- **선행**: W8-T02

### [ ] W8-T04: Windows Inno Setup 인스톨러
- **출력**: `packaging/windows/installer.iss`
- **검증**: Windows 11 사용자가 설치·실행 성공
- **선행**: W8-T02

### [ ] W8-T05: Linux AppImage
- **출력**: `packaging/linux/build.sh`
- **검증**: Ubuntu 22.04에서 더블클릭 실행
- **선행**: W8-T02

### [ ] W8-T06: 진단 도구 `bin/sowing-doctor` 완성
- **출력**:
  - 환경 정보 출력
  - 볼트 무결성 체크
  - 인덱스 일관성 체크
  - 일반적 문제 자동 진단
- **검증**: 5종 이상의 흔한 문제 진단·해결 안내
- **선행**: W7 전체

### [ ] W8-T07: 베타 테스터 5명 모집·피드백 수집
- **출력**:
  - 비공개 베타 모집
  - 피드백 양식
  - 발견된 버그 issue 등록
- **검증**: 5명 모두 30분 내 첫 메모 작성 성공, 7일간 사용 후 회고
- **선행**: W8-T03/T04/T05

### [ ] W8-T08: 출시 준비
- **출력**:
  - GitHub Release 페이지
  - 사용자 안내 문서
  - 알려진 이슈·로드맵 공개
- **검증**: 외부 사용자가 다운로드 → 설치 → 사용 전 과정 자가 완수 가능
- **선행**: W8-T07

### **🎯 Week 8 마일스톤 (= MVP 출시)**
**3개 OS에서 인스톨러를 통한 설치가 가능하고, 베타 사용자가 만족한다.**

---

## 출시 후 즉시 작업 (Week 9~)

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

- 모바일 앱 (Flutter) — Phase 4
- AI 자동 태그 제안 (Ollama 연동) — Phase 3
- 음성 메모 → 텍스트 — Phase 3
- 협업·공유 — Phase 5
- Daily Note 기능 (ADR-003 재검토 시) — Phase 2 이후
