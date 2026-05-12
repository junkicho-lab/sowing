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

## ADR-013: Phase 2 (W9~W24) 는 Software 3.0 전환에 헌정한다

**상태**: Accepted (2026-05-09)

**컨텍스트**

Phase 1 (W1~W8 MVP) 완성 후 [`sowing-docs/EVALUATION.md`](../sowing-docs/EVALUATION.md)
에서 Karpathy의 Sequoia Ascent 2026 12 명제로 Sowing을 점검. 결과:

- ✅ agent-native **데이터 레이어**(마크다운 SoT, 결정적 도메인, 855 spec, doctor·ConsistencyCheck)는 우연히 잘 갖춤
- ❌ agent-facing **표면**(MCP 서버, LLM 합성, 구조화 로그, 머신 가독 문서)이 거의 비어 있음
- ❌ Karpathy가 강조한 "이전엔 코드로 못 만들었지만 LLM으로는 자연스러운" 합성 기능 0
  - 학생별 누적 페이지, 학기말 회고, 수업 패턴, 모순 탐지, 빠진 공백 알림 등

이 격차는 Sowing의 핵심 가치 제안("교사의 *이해* 향상 도구")을 약하게 만든다.
v0.1.0은 기록 도구이지만, 진짜 가치는 합성·통찰에서 나온다.

**결정**

Phase 2 (W9~W24, 16주) 는 Software 3.0 전환에 헌정한다:

- **W9~12 Phase 9**: Agent-Native Surface — MCP 서버 + 구조화 audit log + agent 지침 문서
- **W13~16 Phase 10**: Eval Infrastructure — 한국어 교사 글 100건 코퍼스 + LLM-judge harness + CI 통합
- **W17~20 Phase 11**: Tier-1 LLM 합성 — EntityExtractor + StudentDigest + GapDetector + 검토 UI
- **W21~24 Phase 12**: Tier-2 LLM 합성 — SemesterReflection + LessonPattern + ContradictionDetector

**근거**

1. **Karpathy verifiability 원칙(§1.5)**: Sowing은 검증 가능성을 잘 갖췄다(spec·doctor·SoT). LLM 기능은 검증 환경(Phase 10) 위에 얹는다 — Phase 9 → 10 → 11 → 12 순서 의무.
2. **MenuGen 자기 검토(§1.3)**: 일부 화면은 LLM 직접 변환으로 사라질 수 있음을 인정. 하지만 Sowing의 결정적 동작은 *기본값*, LLM은 *옵션 보강* — 둘 공존.
3. **Ghosts not animals(§1.11)**: LLM은 도구이지 동물이 아님. 의인화 UI 거부 (챗봇 절대 안 만듦).
4. **Understanding not thinking(§1.12)**: 사용자가 글을 *대신 쓰는* LLM은 거부. 합성·요약·연결만 — 글은 교사 본인이 쓴다.
5. **로컬 우선 + 옵트인**: 모든 LLM 기능은 옵션. OpenAI/Anthropic 클라우드 강제 안 함. Ollama 등 로컬 LLM 동등 지원. 사용자 동의 없는 데이터 외부 전송 금지.

**명시적 거부 (Phase 2 전 기간 적용)**

1. ❌ **챗봇 UI** — Sowing 안에 ChatGPT 클론 절대 안 만듦. 외부 에이전트가 MCP로 접근하는 게 정답.
2. ❌ **자동 글쓰기** — LLM이 사용자 대신 메모/필기/기록 작성 안 함. 합성·요약·연결만.
3. ❌ **클라우드 LLM 강제** — 옵트인. 로컬 LLM 동등 지원.
4. ❌ **"AI가 ~ 생각합니다" 의인화 카피** — 도구지 동물 아님 (§1.11).
5. ❌ **자율 에이전트의 vault 변경** — 모든 mutation은 사용자 명시 수락 필요. Audit log 의무.

**결과**

- ✅ Phase 1의 자산 (마크다운 SoT·결정적 도메인·spec·doctor) 위에 LLM 기능을 안전히 얹는 명확한 길.
- ✅ "이전엔 불가능했고 이제 자연스러운" 합성 기능 5종 도입 (EVALUATION §1.4).
- ✅ MCP 서버로 iPhone 17 문제 자연 해결 — ChatGPT 모바일이 Sowing의 sensor·actuator 사용. 별도 iOS 앱 불필요.
- ⚠ Phase 2 모든 작업은 회귀 spec 100% 통과 의무. 1.0 깨지면 release block.
- ⚠ LLM 기능은 도메인 코드의 결정적 인터페이스(`Use Case + Result`)로 감싸 격리. chat-style 통합 금지.

**구현 메모**

- ADR 자체는 본 문서 참조용. 실제 작업 분해는 [`ROADMAP.md`](../ROADMAP.md) Phase 9~12 섹션.
- Phase 2 시작 전 [`sowing-docs/EVALUATION.md`](../sowing-docs/EVALUATION.md) 정독 의무.
- 새 기여자는 [`KICKOFF.md`](../KICKOFF.md) "Phase 2 진입자" 섹션부터 시작.

---

## ADR-014: 동사 중심 IA — 명사 (저장 단위) 와 동사 (의도) 두 계층 명시 분리

**상태**: Accepted (2026-05-11)

**컨텍스트**

Phase 1~12 (W1~W24) 의 누적 기능을 평면 nav 10항목 (`홈 메모 필기 기록 태그 검색 템플릿 합성기 그래프 설정`) 으로 노출. 비교 분석 (`docs/gb-docs.md` — 김교수 "지독한 기록" 영상) 결과 3가지 문제:

1. **평면 분산** — 10개 한 줄, 시각적 hierarchy 0
2. **명사·저장위치 분류** — "메모/필기/기록" 은 폴더 이름. 사용자는 동사로 사고
3. **신규 진입자 혼란** — "메모? 필기? 기록? 차이가 뭐지? 어디부터?"

베타 인터뷰 시 가장 큰 이탈 사유로 예상.

**결정**

사용자 노출 nav 를 **동사 중심** (5+1) 으로 재구성. 내부 저장 단위 (명사 mode) 는 그대로 유지. 두 계층을 명시 분리.

- **명사 mode (저장 단위, 변경 0)**: 메모(00_Inbox) · 필기(20_Notes) · 기록(30_Records) · **계획(40_Plans, W27 신설)** · 합성(.sowing/synth)
- **동사 mode (사용자 의도, nav 노출)**:
  - 🖊 **글쓰기** — 빠른 메모 / 5 subtype (책·강의·감정·학생) / 음성 / 필기 작성
  - 📚 **쓴 글 보기** — 최근 통합 / 카테고리 / 매트릭스 / Timeline / 태그 / 그래프 / 검색
  - 🗓 **쓸 글 계획** — 5 period (daily·weekly·monthly·project·semester)
  - 🪞 **자기 거울** — 17 합성기 + 5축 자아 분석 (W28 self-mirror)
  - 🏠 홈 · ⚙ 설정

**근거**

- 마크다운 SoT (ADR-001) 정체성 100% 유지 — 폴더 구조·옵시디언 호환·30년 누적 모두 변경 0
- 기존 라우트 (`/memos /notes /records /tags /search /synth /graph`) 모두 그대로 작동 — 북마크·외부 링크 호환
- 신규 라우트 (`/write /view /plan /mirror`) 추가 진입점 역할
- 동사 중심은 김교수 "지독한 기록" 영상이 검증한 UX (대시보드·기록하기·기록 보기·피드백·계획 5 메뉴) 의 일반화

**결과**

✅
- 신규 사용자 첫 메모까지 시간 목표 < 30초 (현재 ~2분)
- 1주차 이탈률 목표 < 20% (현재 ~40% 예상)
- Nav hover 횟수 목표 < 1.5회 (현재 3.2회)
- 합성기 월 사용률 목표 > 60% (현재 ~30%)

⚠
- 기존 사용자 nav 재학습 필요 — W25-T02 의 1회 안내 모달로 완화
- 명사/동사 두 계층 유지 비용 (라우트 수 ↑, 일부 spec 명사 매치 → URL 존재 검사 패턴으로 갱신)

**구현 메모**

- Phase 13 (W25~W28, 2026-05-11 일괄) 에 PoC 완료:
  - W25-T01 nav 5+1 + `<details>` dropdown (JS 0)
  - W25-T02 1회 변경 안내 모달 (`Settings.ia_v2_seen_at`)
  - W26-T01 빠른 메모 5 subtype (book/lecture/emotion/student/일반) — 도메인 변경 0, client-side body 결합
  - W26-T02 음성 입력 (Web Speech API ko-KR, Whisper.cpp 로컬 W26-T02b 예정)
  - W26-T03 `/view/recent` 통합 시간순 페이지
  - W27-T01 Plan 도메인 + 40_Plans/ + PlanRepo
  - W27-T02 5 period (project/semester 추가) + 대시보드 "오늘 할 일" 위젯
  - W28-T01 17번째 합성기 SynthesizeSelfMirror (5축)
  - W28-T02 대시보드 "오늘의 자기" 위젯 (opt-in)
  - W28-T03 자동 매일 생성 hook (검토 대기 폴더 유지 — ADR-013 호환)
- spec 1430 → 1607 (+177), 캡쳐 13 → 24 (+11)
- 상세 설계 문서: [docs/REDESIGN_IA.md](REDESIGN_IA.md)

---

## ADR-015: Note mode 폐기 — Knowledge::Record 로 흡수

**상태**: Accepted (2026-05-12)

**컨텍스트**

사용자 비전 (MVP_VISION §B) 의 입력 자료 4종 = 메모·공부·보고서·계획서.
"공부" 와 "보고서" 의 경계가 사용자 의도상 모호 — 둘 다 정리·체계.
현재 Sowing v0.1.8 은 4 mode (Memo·Note·Record·Plan) — Note 가 어디에
위치하는지 사용자 의도 불명.

옵션 검토:
- A. Note 유지 → Knowledge::Reference (공부) + Knowledge::Record (보고) 분리
- B. **Note 폐기 → Knowledge::Record 로 흡수**
- C. Note 유지 → Knowledge::Reference 로 통일 (자료 + 정리)

**결정**

옵션 B. Note 폐기. 기존 `Note` 도메인을 `Knowledge::Record` 로 흡수.

v0.2.0 부터 3 명사 mode (`Capture::Item` + `Knowledge::Record` +
`Knowledge::Plan`) + Synth + Template.

**근거**

- 사용자 비전과 정합 (4 입력 자료가 Memo·Reference·Report·Plan 으로 명시
  안 되어 있음 — 사용자 본인은 메모·자료·보고서·계획서 로 표현)
- 옵션 A 는 도메인 객체 1개 추가 — Bounded Context 복잡도 증가
- 옵션 C 는 의미 변경만 — rename 부담은 같지만 가치 약함
- B 가 가장 단순 + 사용자 비전 정합

**결과**

✅
- 4 mode → 3 mode (Memo·Record·Plan + 합성·Output)
- 사용자 UX 진입점 단순화 ('필기 작성' → '기록 작성' 으로 통합)

⚠
- 기존 20_Notes/{카테고리}/*.md 파일 → 30_Records/{YYYY}/{카테고리}/*.md
  로 이전 마이그레이션 필요
- Stage 5 폐기 단계까지 `Note` 는 alias 로 작동 (Strangler Fig)
- 기존 사용자 노트 마이그레이션 — 자동 변환 + 사용자 검토 단계 필수

**구현 메모**

- Phase R3 (Stage 3) 의 R3-T03 `Knowledge::Domain::Reference` 옵션 삭제
- Phase R5 (Stage 5) 의 R5-T01 에 Note 폴더 마이그레이션 + alias 제거
- 마이그레이션: 모든 note row 의 mode='note' → 'record' (DB) + 파일 이동 (vault)
- 결정 trace: [docs/REFACTORING_DECISIONS.md#게이트-1](REFACTORING_DECISIONS.md)

---

## ADR-016: Subject 4축 제약 분류 도입

**상태**: Accepted (2026-05-12)

**컨텍스트**

사용자 비전 D — 판단 기준 4축 (인물·교과·계획서·정체성). 현재 Sowing
v0.1.8 은 자유 카테고리만 (사용자 정의 문자열, 예: 'lessons'·'수업회고'
·'상담' 등). 4축 명시 분류가 없어 모든 출력 (E.2 주제별·E.3 용도별) 의
기반이 약함.

**결정**

모든 entry (Memo·Record·Plan·Synth) 에 `subject` 메타데이터 추가.
4 enum 값 (`person · subject · document · identity`) 으로 제약.

자유 카테고리 (소분류) 는 그대로 유지 — `subject` 는 상위 4축, `category`
는 하위 자유 분류. 두 축 공존.

**근거**

- 비전 D 직접 충족 — 4 분류 명시
- 출력 (E.2 주제별 / E.3 용도별) 의 기반
- 자유 카테고리 와 별도 — 사용자 선택 영역 축소 없음
- nullable — 기존 데이터 호환 (Stage 5 후 NOT NULL 고려)

**결과**

✅
- 비전 D·E.2·E.3 의 도메인 기반 확보
- Subject × 연도 매트릭스 (기존 카테고리 × 연도 옆 추가)
- /view/recent 의 4 subject chip 필터
- Output Template (생기부·상담부 등) 의 자동 입력 수집 기반

⚠
- **명명 충돌 의식**: 'Subject 4축' (개념) vs `:subject` (enum 값 — 교과 의미)
  - 코드: 상수 `CURRICULUM_SUBJECT = :subject` 권장
  - 문서: 한글 "교과" + enum 키 병기
  - URL: `?subject=person|subject|document|identity`
- 기존 entry 의 `subject = NULL` 그대로 작동 — UI 에 "미분류" 표시

**구현 메모**

- Phase R2 (Stage 2) 의 R2-T06 마이그레이션 008: `entries.subject` column
- Phase R3 (Stage 3) 의 R3-T11 reclassify 도구 — 카테고리 → subject 자동 제안
  매핑:
  - 학생기록·상담·학생관찰 → `:person`
  - 수업·수업회고·평가·도덕 → `:subject`
  - 회의·행사·사업·학급운영 → `:document`
  - 학기회고·자기회고·교육철학 → `:identity`
- 결정 trace: [docs/REFACTORING_DECISIONS.md#게이트-2](REFACTORING_DECISIONS.md)

---

## ADR-017: Archive 메타데이터 — active vs archived 이분

**상태**: Accepted (2026-05-12)

**컨텍스트**

사용자 비전 C — 처리 흐름 5단계 중 "대상학생·학년도 지나면 **이관**".
30년 누적이 무거워지면 일상 회상이 압도됨.

옵션 검토:
- 폴더 분리 (`Archived/`): 옵시디언 호환 좋지만 폴더 구조 변경 큼
- 메타데이터 (`archived_at` timestamp): 폴더 그대로, 필터로 분리

**결정**

`entries.archived_at` (ISO8601) + `archive_reason` (text) 컬럼 추가.
폴더 구조 변경 없음 (옵시디언 호환 유지).

**근거**

- 폴더 변경 0 — 옵시디언 vault 그대로
- `WHERE archived_at IS NULL` 한 줄로 일상 회상 필터
- archive 보존 — 옛 자료 검색 가능 (`?include_archived=1`)
- 졸업·학년종료·사업종료 등 사유 (`archive_reason`) 분류

**결과**

✅
- 일상 UX 무거워짐 0 — 검색·합성기·view_recent 모두 `IS NULL` 필터
- 30년 누적 시 자연스러운 정리 흐름
- 명시적 unarchive 가능 (사용자 클릭, ADR-013)
- 보관함 (`/archive`) 페이지 — archive 검색·복원 전용

⚠
- 모든 query 에 `archived_at IS NULL` 추가 — 누락 위험 (linter 또는 default scope?)
- 일괄 archive 동작의 안전성 (잘못 archive 하면 사용자 혼란)
  - 완화: 학생별·학년도별 archive 시 명시 confirm + 일괄 unarchive UI

**구현 메모**

- Phase R3 (Stage 3) R3-T05 ~ R3-T09
- 마이그레이션 009: `entries.archived_at` + `archive_reason` + index
- IndexRepo 의 모든 일상 query 에 `IS NULL` 필터
- audit log 에 archive/unarchive 명시 기록 (ADR-013)
- 결정 trace: [docs/REFACTORING_DECISIONS.md#게이트-1](REFACTORING_DECISIONS.md)

---

## ADR-018: Template-based Export — 사용자 편집 가능 ERB 5종

**상태**: Accepted (2026-05-12)

**컨텍스트**

사용자 비전 E.3 — 용도별 출력 5종 (생기부·상담부·회의록·사업계획서·예산
요구서). 학교별·연도별 양식 차이 큼 — hardcoded ERB 는 부적합.

**결정**

`10_Templates/exports/*.erb` 사용자 편집 가능 ERB template. 5종 모두 MVP
포함 (게이트 #3 c). 출력 형식 3종: Markdown (default) / PDF (Prawn) /
DOCX (caracal).

**근거**

- 학교별 양식 차이 — 사용자가 ERB 직접 편집
- 한글 폰트 (Pretendard) Prawn 호환 확인됨
- DOCX 는 caracal — ruby native, 외부 도구 (LibreOffice) 불필요
- 5종 모두 MVP 포함 — 비전 E.3 완전 충족 (게이트 #3 c)

**결과**

✅
- 학교별·연도별 양식 차이 자체 흡수
- v0.2.0 day 1 에 5 용도 모두 출력 가능
- Markdown 출력 → 옵시디언·iA Writer 등 외부 도구로 추가 편집

⚠
- 5 template 양식 검증 부담 — 베타 1명 검토 필수 (게이트 #8)
- Prawn 한글 폰트 packaging — 배포 크기 +5MB 정도
- 사용자가 ERB 편집 잘못하면 export 실패 — error 핸들링 + 디폴트 폴백

**구현 메모**

- Phase R4b (Stage 4b) — Week 38~39
- `10_Templates/exports/` 5 ERB 파일
- `Output::Exporter::{Markdown,Pdf,Docx}Exporter` — Strategy 패턴
- `/export` 페이지 — 5 template 선택 chip + 입력 폼 (학생·날짜·사업명 등)
- spec ~80 (template 별 16 case)
- 결정 trace: [docs/REFACTORING_DECISIONS.md#게이트-3](REFACTORING_DECISIONS.md)

---

## ADR-019: Bounded Context 4 모듈 — Strangler Fig 패턴

**상태**: Accepted (2026-05-12)

**컨텍스트**

Phase 1~14 동안 누적된 `lib/sowing/{controllers,repositories,use_cases,
domain,infrastructure}/` 평면 구조. v0.2.0 의 비전 충족 (Subject 4축·
Archive·Export 5종) 추가 시 평면 구조 복잡도 한계.

Eric Evans 의 Bounded Context (DDD) 로 4 모듈 분리. Martin Fowler 의
Strangler Fig 패턴으로 점진 이전.

**결정**

4 Bounded Context 모듈:

1. **Capture** (포착) — Memo → CaptureItem
2. **Knowledge** (지식) — Record·Plan + Archive
3. **Insight** (통찰) — 17 합성기·자기 거울
4. **Output** (출력) — Template Export 5종

의존 방향 (acyclic):

```
              Output
                ▲
                │
       Knowledge ↔ Insight
                ▲
                │
              Capture (base)
```

모듈 간 인터페이스: 각 모듈의 `public_api.rb` Façade. 내부 클래스 직접
참조 금지.

8주 Strangler Fig: 새 모듈 옆에 짓고, 라우트 점진 이전, Stage 5 에 옛
코드 제거.

**근거**

- DDD Bounded Context — 비전 A~E 의 도메인 경계 명확
- Strangler Fig — 한 번에 갈아엎지 않음, 가역성 확보
- 의존 acyclic — 단방향, 양방향 의존 금지 (`bin/sowing-arch-check` 자동 검증)
- Façade 패턴 — 모듈 간 결합도 낮춤

**결과**

✅
- 비전 A~E 명시 도메인 경계
- 새 기능 추가 시 어느 모듈인지 명확
- 모듈 단독 spec 가능 (다른 모듈 mock)
- `bin/sowing-arch-check` 자동 검증

⚠
- 8주 작업 — 단일 개발자 (Claude + 사용자) full speed
- 마이그레이션 008·009 위험 — vault 백업 + Feature Flag 필수
- Strangler Fig 중간 상태 (옛+새 공존) 복잡 — 각 stage 끝 release-check 통과 의무

**구현 메모**

- Phase R1~R5 (W33~W40, 2026-05-19 ~ 2026-07-07)
- 사용자 합의 게이트 9개 — Stage 0 5건 완료, 6~9 진행 중 확인
- 9 (final v0.2.0) 합의 없으면 v0.1.9 부분 출시 옵션
- 상세 청사진: [docs/REFACTORING_BLUEPRINT.md](REFACTORING_BLUEPRINT.md)
- 합의 trace: [docs/REFACTORING_DECISIONS.md](REFACTORING_DECISIONS.md)

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
