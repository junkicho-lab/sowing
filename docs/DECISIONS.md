# 아키텍처 의사결정 기록 (Architecture Decision Records)

본 문서는 본 프로젝트에서 내려진 주요 설계 결정과 그 근거를 기록합니다. 새로운 결정이 추가되면 번호를 증가시켜 추가하고, 기존 결정을 뒤집을 때는 새 ADR을 작성하여 이전 결정을 supersede 합니다.

ADR 형식: [Michael Nygard 형식](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/locales/en/templates/decision-record-template-by-michael-nygard/index.md)

---

## ADR-001: 옵시디언 호환 마크다운을 Single Source of Truth로 한다

**상태**: Accepted (2026-05-07)

**컨텍스트**

본 앱은 옵시디언 학습 부담을 낮추는 것을 핵심 가치 제안으로 한다. 데이터를 어디에 어떤 형식으로 저장할 것인가는 본 앱의 정체성을 결정한다.

**고려한 대안**

1. SQLite에 모든 콘텐츠 저장, 옵시디언 호환 마크다운으로 export 기능 제공
2. 마크다운 파일에 모두 저장, SQLite는 인덱스만
3. 독자 바이너리 포맷 사용

**결정**

옵션 2 채택. 모든 콘텐츠는 처음부터 옵시디언 볼트 구조의 마크다운으로 저장된다. SQLite는 검색 인덱스·동기화 메타데이터만 저장한다.

**근거**

- 본 앱이 사라져도 사용자 데이터가 옵시디언으로 그대로 살아남는다 (사용자 신뢰의 핵심)
- "옵시디언으로 졸업"이 자연스럽게 일어난다 — 별도 마이그레이션 불필요
- SQLite를 삭제·재구축해도 데이터 손실 없음

**결과**

- ✅ 사용자 데이터 lock-in 없음
- ✅ 옵시디언 사용자가 곧바로 본 앱을 시도해 볼 수 있음
- ⚠ 외부 변경 감지·동기화 로직이 복잡해짐 (FileWatcher 필요)
- ⚠ 한국어 전문 검색이 SQLite FTS의 한계에 영향받음

---

## ADR-002: 백엔드는 Sinatra 로컬 웹 서버로 한다

**상태**: Accepted (2026-05-07, 사용자 확정)

**컨텍스트**

데스크톱 앱 형태로 Ruby 앱을 배포할 때 GUI 옵션은 (a) Glimmer DSL for LibUI 등 네이티브 GUI, (b) 로컬 웹 서버 + 브라우저, (c) Tauri 등 웹뷰 래퍼 가 있다.

**결정**

(b) Sinatra 로컬 웹 서버 + 브라우저 선택. 사용자는 앱 실행 시 자동으로 기본 브라우저에서 `http://127.0.0.1:48723` 이 열린다.

**근거**

- 모던 UI 구현 자유도 (Hotwire 활용)
- 단일 코드베이스로 macOS·Windows·Linux 동일 동작
- 추후 모바일·웹 확장 시 코드 재사용 용이
- 디버깅·개발 도구 풍부 (브라우저 DevTools)
- 키오스크/포커스 모드는 추후 별도 wrapper로 추가 가능

**결과**

- ✅ 빠른 UI 구현
- ✅ Hotwire의 서버 렌더링이 Ruby 친화적
- ⚠ 브라우저가 별도 창으로 떠서 "앱"같지 않다는 사용자 인식 우려 → 시스템 트레이 wrapper로 보완
- ⚠ 글로벌 단축키는 OS 레벨 helper(menubar app 등) 별도 구현 필요

---

## ADR-003: MVP에서 일일 노트(Daily Note) 기능을 제외한다

**상태**: Accepted (2026-05-07, 사용자 확정)

**컨텍스트**

옵시디언 사용자의 가장 흔한 패턴은 Daily Note (날짜별 자동 생성 노트). 이를 MVP에 포함할지 검토했다.

**결정**

MVP에서 제외. Phase 2 이후 도입 검토.

**근거**

- 메모/필기/기록 3축이 본 앱의 차별화 컨셉인데, Daily Note는 4번째 축이 되어 인지 부하 증가
- "오늘 한 일을 모두 한 곳에 적는다"는 Daily Note 패턴은, 본 앱의 "메모는 던져두고 필요할 때 승격" 흐름과 약간 충돌
- MVP에서는 8개 메뉴(홈/메모/필기/기록/검색/태그/통계/설정)만으로도 신규 사용자에게 충분히 풍부함
- Phase 2 이후 사용자 피드백을 보고 추가하는 것이 위험 부담 적음

**결과**

- ✅ MVP 범위 축소
- ✅ 핵심 컨셉 명료성 유지
- ⚠ 옵시디언 베테랑 사용자가 익숙한 패턴 부재로 어색해할 가능성 (낮음 — 본 앱 1차 타깃은 베테랑이 아님)

---

## ADR-004: 위키링크 자동완성에 메모 파일도 포함한다

**상태**: Accepted (2026-05-07, 사용자 확정)

**컨텍스트**

`[[` 입력 시 자동완성 후보를 어떻게 구성할지. 메모는 휘발성·비공식 성격이라 검색 결과에서 제외할 수도 있다.

**결정**

메모 파일도 자동완성 후보에 포함한다. 단 시각적으로 모드를 구분 표시한다 (`💭 메모` / `📝 필기` / `📖 기록`).

**근거**

- 메모와 기록을 잇는 "현장의 단편"이 사용자에게 가장 자주 떠오르는 단서
- 휘발성이라고 해서 참조 못 하게 만드는 것은 사용자의 사고 흐름을 방해
- 옵시디언도 모든 파일을 자동완성 후보로 노출함 (호환성)

**결과**

- ✅ 자유로운 사고 흐름 지원
- ⚠ 자동완성 결과가 너무 많아질 가능성 → 정렬 우선순위는 (1) 최근 작성, (2) 모드 (record > note > memo), (3) 제목 일치도

**구현 메모**

자동완성 응답 형식:
```json
{
  "results": [
    {"path": "30_Records/2026/...", "title": "민호 진로상담 기록", "mode": "record", "icon": "📖"},
    {"path": "20_Notes/lessons/...", "title": "지구과학 단원 정리", "mode": "note", "icon": "📝"},
    {"path": "00_Inbox/2026-05-07_...", "title": "(메모) 1교시가 활기찼다", "mode": "memo", "icon": "💭"}
  ]
}
```

메모는 제목이 없으므로 본문 첫 60자를 `(메모) ...` 형식으로 표시.

---

## ADR-005: 첫 실행 시 샘플 콘텐츠를 미리 채운다

**상태**: Accepted (2026-05-07, 사용자 확정)

**컨텍스트**

신규 사용자가 빈 볼트를 마주했을 때의 막막함을 어떻게 줄일 것인가.

**결정**

첫 실행 시 사용자 동의를 받아 12종의 샘플 콘텐츠를 볼트에 자동 생성한다. 모두 가상의 교사 페르소나가 작성한 형태이며, 본 앱의 기능을 실사용 맥락으로 보여준다.

**근거**

- "빈 화면 금지 원칙" (SPEC §10.1)
- 사용자가 자신의 첫 글을 쓰기 전에 "이런 식으로 쓰는구나"를 학습할 수 있는 모범 예
- 메모/필기/기록 3단계 차이를 텍스트로 설명하기보다 실제 예시로 보여주는 것이 효과적
- 위키링크·태그 활용도 자연스럽게 노출

**결과**

- ✅ 신규 사용자 온보딩 마찰 극적 감소
- ⚠ 사용자 데이터 오염 우려 → 다음으로 완화:
  1. 첫 실행 시 명시적 동의 확인 ("샘플을 추가할까요? Yes/No")
  2. 모든 샘플은 `templates/samples/` 폴더 하위로 격리
  3. 모든 샘플 frontmatter에 `is_sample: true` 표시
  4. 설정에서 "샘플 모두 삭제" 메뉴 제공

**구현 메모**

샘플 12종 구성:
- 메모 4종 (다양한 시점·길이)
- 필기 4종 (수업 정리/연수 메모/책 노트/회의록 각 1)
- 기록 4종 (학급운영/학생 관찰/수업 성찰/교사 성장 각 1)

샘플 콘텐츠는 본 명세 작성자가 한국 교사 일상을 반영하여 직접 작성한다.

---

## ADR-006: 클라우드 동기화 가이드를 앱이 직접 안내한다

**상태**: Accepted (2026-05-07, 사용자 확정)

**컨텍스트**

본 앱은 자체 클라우드 동기화 서버를 운영하지 않는다 (ADR-001과 비목표). 그러나 사용자가 여러 기기에서 같은 볼트를 사용하고 싶은 니즈는 자연스럽게 발생한다.

**결정**

설정 화면에 "다른 기기와 동기화하기" 가이드를 직접 노출한다. iCloud Drive, OneDrive, Dropbox, Syncthing 4종의 사용법을 OS별로 안내한다.

**근거**

- 옵시디언 공식 동기화(Obsidian Sync)는 유료. 교사 사용자에게 부담이 될 수 있음
- 무료 솔루션의 설정이 비기술 사용자에게 어려움
- 잘못된 동기화 설정으로 인한 데이터 충돌·손실 위험을 본 앱이 안내함으로써 줄일 수 있음
- 본 앱이 옵시디언으로 가는 다리 역할을 한다는 컨셉과 부합

**결과**

- ✅ 사용자 부담 경감
- ✅ 데이터 안전성 가이드 제공
- ⚠ 외부 서비스(iCloud 등)가 변경되면 가이드 업데이트 필요 → 가이드는 앱에 하드코딩하지 않고 마크다운으로 `templates/guides/` 에 배포 → 앱 업데이트로 갱신

**구현 메모**

가이드 콘텐츠는 다음 4종 + OS 매트릭스:

| 솔루션 | macOS | Windows | Linux |
|--------|-------|---------|-------|
| iCloud Drive | ✅ | ⚠ (제한) | ❌ |
| OneDrive | ✅ | ✅ | ⚠ |
| Dropbox | ✅ | ✅ | ✅ |
| Syncthing | ✅ | ✅ | ✅ |

각 가이드는 (a) 설치 링크, (b) 볼트 폴더 이동 절차, (c) 충돌 발생 시 대처법, (d) 권장 사용 시나리오를 포함한다.

설정 화면 위치: `설정 > 백업과 동기화 > 동기화 가이드`

---

## ADR-007: 데이터베이스 ORM은 Sequel을 사용한다 (ActiveRecord 아님)

**상태**: Accepted (2026-05-07)

**컨텍스트**

Ruby ORM 양대 산맥은 ActiveRecord와 Sequel.

**결정**

Sequel 채택.

**근거**

- 본 앱은 Rails가 아님. ActiveRecord의 컨벤션 강제는 Sinatra 환경에서 더 이상 자연스럽지 않음
- Sequel의 명시적 dataset API가 본 앱의 검색·인덱싱 로직(JOIN, FTS5 가상 테이블 등)에 더 적합
- 마이그레이션 파일이 깔끔
- 의존성이 가벼움 (ActiveRecord는 ActiveSupport 등 풀 의존)

**결과**

- ✅ 가벼움
- ✅ 명시적 SQL 매핑
- ⚠ Rails 출신 엔지니어는 짧은 적응 기간 필요 → CLAUDE.md에 패턴 예시 포함

---

## ADR-008: 프론트엔드는 Hotwire (Turbo + Stimulus) 만 사용한다

**상태**: Accepted (2026-05-07)

**컨텍스트**

JS 프레임워크 선택지: React, Vue, Svelte, Hotwire, vanilla JS.

**결정**

Hotwire 채택. JS 빌드 도구(Webpack, Vite 등) 도입하지 않음.

**근거**

- Ruby 생태계 정합성
- 빌드 도구 없음 → 개발 환경 단순, Tebako 패키징과 충돌 없음
- 교사 일상 기록 앱 수준의 인터랙션은 Turbo Stream + Stimulus로 충분
- SEO 불필요 (로컬 앱)이지만 서버 렌더링의 응답 속도 이점 활용
- CodeMirror 6은 ESM CDN으로 직접 로드

**결과**

- ✅ 빌드 단계 제거
- ✅ Ruby 백엔드와 1:1 응답
- ⚠ 일부 복잡한 인터랙션(예: 드래그 앤 드롭으로 메모 승격)은 vanilla JS Stimulus 컨트롤러로 직접 작성 필요

---

## ADR-009: 패키징은 Tebako로 단일 실행파일을 만든다

**상태**: Proposed (검증 필요)

**컨텍스트**

Ruby 앱을 비기술 사용자에게 배포하려면 Ruby 런타임·gem 의존성 없이 더블클릭으로 실행 가능해야 한다.

**결정**

Tebako 채택. 백업 옵션으로 traveling-ruby 또는 native gem 번들도 검토.

**근거**

- Tebako는 Ruby 3.x 지원
- 단일 실행파일로 패키징 (사용자가 별도로 Ruby 설치 안 함)
- Docker 기반 빌드로 재현성 우수

**결과**

- ✅ 비기술 사용자 배포 용이
- ⚠ Tebako 빌드 시간 길고, OS별로 별도 빌드 필요 → CI 파이프라인 구성 필요
- ⚠ macOS의 경우 codesign + notarize 별도 필요

**향후 검토 사항**

W7~W8에 Tebako 빌드 검증. 실패 시 traveling-ruby로 fallback 결정 필요.

---

## ADR-010: i18n은 r18n을 사용하고 첫 출시는 한국어만 지원한다

**상태**: Accepted (2026-05-07)

**컨텍스트**

다국어 지원 시기와 도구 선택.

**결정**

i18n 구조는 처음부터 r18n으로 설계하되 출시는 한국어만. Phase 2 이후 영어 검토.

**근거**

- 1차 타깃이 대한민국 교사이므로 영문 번역에 자원 분산 비효율
- i18n 구조가 처음부터 있어야 나중에 도입 비용 적음
- r18n은 gettext 호환·서버사이드 친화적

**결과**

- ✅ 한국어 우선 폴리싱에 자원 집중
- ✅ 향후 다국어 도입 시 마이그레이션 적음

---

## ADR-011: Ruby 4.0.x 지원을 위한 부트스트랩 의존성 핀 상향

**상태**: Accepted (2026-05-07)

**컨텍스트**

W1-T01 환경 검증 단계에서 사용자의 mise 글로벌 Ruby가 4.0.3으로 업데이트된 상태였고, 사용자 지시로 현재 설치된 Ruby(4.0.3)를 그대로 사용하기로 함. 그러나 Gemfile의 일부 핀이 Ruby 4.x 미지원이었음:

- `r18n-core ~> 5.0` — gemspec이 `Ruby >= 2.5, < 4` 제약
- `commonmarker ~> 1.1` — Ruby 4.0 환경에서 C 확장 빌드 실패 (사전 빌드 바이너리 없음)

**결정**

다음 핀을 상향한다 (외부 gem 교체 없이 같은 패밀리의 더 새로운 메이저 버전 사용):

- `r18n-core ~> 5.0` → `~> 6.0`
- `commonmarker ~> 1.1` → `~> 2.8`
- `Gemfile`의 `ruby "3.3.0"` → `ruby ">= 3.3.0"`
- `.ruby-version` `3.3.0` → `4.0.3`

**근거**

- r18n-core 6.0.0은 동일 API 패밀리, Ruby 4.x 호환. ADR-010의 r18n 선택은 유지됨.
- commonmarker 2.8.1은 arm64-darwin/x86_64-darwin 사전 빌드 바이너리 제공 → 컴파일러 의존성 제거.
- 대안(Ruby 3.3.0 재설치)은 사용자 환경에서 거부됨 (사용자 지시).
- 대안(다른 i18n gem 교체)은 ADR-010 결정 자체를 뒤집는 더 큰 변경.

**결과**

- ✅ Ruby 4.0.3 환경에서 `bundle install` 성공 (101 gems).
- ✅ ADR-010(r18n 선택), ADR-008(Hotwire), ADR-007(Sequel) 등 핵심 스택 결정 유지.
- ⚠ commonmarker 1.x → 2.x는 메이저 점프이며 API 변경 가능성. W1-T06(VaultRepo: markdown serializer/parser) 구현 시 commonmarker 2.x API에 맞춰 작성 필요.
- ⚠ r18n-core 5.x → 6.x도 메이저 점프이며 W2 이후 i18n 코드 작성 시 6.x 변경점 확인 필요.

**구현 메모**

- W1-T06 진입 시 `Commonmarker.to_html` 등 새 API 점검 (`docs/SPEC.md` §9 마크다운 처리 항목 갱신 권장).
- `Gemfile.lock`은 본 ADR과 함께 커밋되어 있음.

---

## ADR-012: 외부 인코딩을 부팅 시점에 UTF-8로 강제한다

**상태**: Accepted (2026-05-08)

**컨텍스트**

W1-T06/1(SafeWriter) 검증 단계에서, 실행 환경의 `Encoding.default_external`이 `US-ASCII`로 설정되어 있어 다음 문제가 발생:

- `File.read`/`Pathname#read`로 읽은 UTF-8 파일이 `US-ASCII`로 라벨링됨
- UTF-8 문자열 리터럴(`"내용"`)과 비교 시 인코딩 불일치로 실패
- spec에서 `File.read(path, encoding: "UTF-8")` 워크어라운드 헬퍼 사용 중

Sowing은 한국어 사용자 대상의 데스크톱 앱이고, 옵시디언 마크다운 호환성 원칙(SoT)에 따라 모든 콘텐츠는 UTF-8이다. 시스템 locale에 의존하는 인코딩 정책은 다음 환경에서 깨짐:

- `LANG=C` / `LANG=POSIX` 환경 (일부 CI, Docker 슬림 이미지)
- Tebako 패키징된 단일 실행 파일 (locale 환경변수 보장 안 됨)
- Windows의 ANSI 코드 페이지가 UTF-8이 아닌 환경

**결정**

`config/application.rb` 부팅 가장 앞단에 다음을 추가한다:

```ruby
Encoding.default_external = Encoding::UTF_8
# default_internal은 의도적으로 nil 유지
```

모든 앱 진입점(`bin/sowing`, `bin/sowing-doctor`, `config.ru`, `spec_helper.rb`)이 `config/application.rb`를 require하므로 단일 지점에서 정책 적용 충분.

**근거**

- **default_external만 설정**: 읽은 파일을 UTF-8로 라벨링. Ruby 기본 동작과 일치, 모든 표준 File API가 자연스럽게 UTF-8 처리.
- **default_internal은 nil 유지**: Ruby가 외부→내부 자동 변환을 비활성화. 비-UTF-8 외부 파일을 만났을 때 즉시 `Encoding::UndefinedConversionError`로 raise하지 않고, 사용 시점에 검출되도록 함 (permissive). 옵시디언 외 도구가 우연히 latin1 파일을 만들었을 때도 우리 앱이 즉시 폭발하지 않음.
- **SafeWriter는 binary 모드 유지**: 쓰기는 항상 `File.open(path, "wb")` — 인코딩 변환 없이 바이트 그대로. 읽기 정책이 변해도 영향 없음.

**결과**

- ✅ spec의 인코딩 워크어라운드 제거 가능 (`safe_writer_spec.rb`의 `read_utf8` 헬퍼 삭제).
- ✅ 향후 Markdown::Parser, Reader 등 모든 read 코드가 별도 옵션 없이 UTF-8 보장.
- ✅ Tebako 패키징 후에도 동일 동작 보장.
- ⚠ 비-UTF-8 외부 파일은 사용 시점에 mojibake 또는 Encoding 에러 가능 — 옵시디언 호환성 검증(W1-T06/2 이후 spec/compatibility)에서 처리.

**구현 메모**

- 본 정책은 모든 spec에도 자동 적용됨 (spec_helper → config/application).
- 향후 새 진입점(rake 태스크 등)을 만들 때 `config/application.rb`를 require하면 정책 자동 적용.

---

## 새 ADR 추가 가이드

새 결정을 기록할 때:

1. ADR 번호를 1 증가
2. 다음 템플릿 사용:

```markdown
## ADR-NNN: 제목 (동사형, 단정형)

**상태**: Proposed | Accepted | Deprecated | Superseded by ADR-XXX (날짜)

**컨텍스트**

(왜 이 결정이 필요한가, 어떤 선택지가 있는가)

**결정**

(무엇을 결정했는가, 한 문장으로 명확히)

**근거**

(왜 이 선택인가, 다른 대안은 왜 배제했는가)

**결과**

(이 결정의 결과로 얻는 것 ✅ / 감수해야 하는 것 ⚠)

**구현 메모** (선택)

(구현 시 알아야 할 구체적 사항)
```

3. PR로 제출하고 사용자 승인 후 머지.
4. ADR이 다른 ADR을 뒤집으면, 이전 ADR의 상태를 `Superseded by ADR-NNN`으로 갱신.
