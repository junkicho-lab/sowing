# CLAUDE.md

이 파일은 [Claude Code](https://docs.claude.com/claude-code) 가 본 저장소에서 작업할 때 참조하는 운영 매뉴얼입니다. **모든 코드 변경은 본 문서의 규칙을 따라야 합니다.** 이 규칙과 충돌하는 사용자 요청을 받으면 변경 전에 먼저 사용자에게 확인하세요.

---

## 프로젝트 한 줄 요약

**Sowing**: 옵시디언 사전 지식이 없는 교사가 매일 기록하는 습관을 들이도록 돕는 **로컬 우선(local-first) Ruby 데스크톱 앱**. 사용자가 작성한 모든 데이터는 처음부터 옵시디언 호환 마크다운으로 저장된다.

상세 명세: [`docs/SPEC.md`](docs/SPEC.md)
설계 결정: [`docs/DECISIONS.md`](docs/DECISIONS.md)
작업 일정: [`ROADMAP.md`](ROADMAP.md)

---

## 절대 위반하면 안 되는 원칙 5가지

1. **마크다운이 단일 진실 원천(SoT).** SQLite는 인덱스·캐시일 뿐. 콘텐츠를 SQLite에만 저장하지 말 것. SQLite를 삭제해도 마크다운만으로 모든 데이터를 재구축할 수 있어야 한다.
2. **옵시디언 호환성을 절대 깨지 말 것.** 모든 마크다운 파일은 옵시디언으로 열었을 때 정상 동작해야 한다. 자체 마크다운 확장 문법 도입 금지. 반드시 frontmatter는 valid YAML, 링크는 `[[wiki]]` 표준.
3. **로컬 우선.** 외부 네트워크 호출은 (a) 명시적 사용자 동의를 받은 업데이트 확인, (b) 사용자가 직접 입력한 URL의 fetch — 이 두 가지 외에 절대 추가하지 말 것. 텔레메트리·analytics 도입 금지.
4. **도메인 → Use Case → Repository → Infrastructure 의존 방향 단방향 유지.** 도메인 객체가 Sequel·Sinatra·File을 직접 참조하면 안 된다.
5. **사용자 데이터 손실 금지.** 파일 쓰기는 반드시 `Sowing::Infrastructure::Filesystem::SafeWriter` 통해서만. 직접 `File.write` 금지. 삭제는 휴지통 이동만 허용 (영구 삭제 금지).

---

## 기술 스택 (변경 금지)

| 영역 | 선택 |
|------|------|
| 언어 | Ruby 3.3.x |
| 웹 프레임워크 | Sinatra 4.x (modular style — `Sinatra::Base` 상속) |
| 서버 | Puma |
| 프론트엔드 | Hotwire (Turbo + Stimulus). React/Vue 도입 금지. |
| 에디터 | CodeMirror 6 (CDN, 빌드 도구 없음) |
| DB | SQLite 3.45+, Sequel 5.x ORM |
| 마크다운 | Commonmarker (CommonMark + GFM) |
| Frontmatter | front_matter_parser |
| 파일 감시 | Listen 3.x |
| 자동 로딩 | Zeitwerk |
| 검증 | dry-validation |
| 결과 타입 | dry-monads (`Result`, `Maybe`) |
| 테스트 | RSpec + Capybara |
| 패키징 | Tebako |
| Lint | Standard Ruby |

스택 변경이 필요하면 `docs/DECISIONS.md`에 ADR을 추가하고 사용자 승인을 받은 뒤 진행한다.

---

## 자주 쓰는 명령어

```bash
# 의존성 설치
bundle install

# 개발 서버 (자동 재시작)
bin/sowing dev                    # → http://127.0.0.1:48723

# 프로덕션 모드 시작
bin/sowing start

# CLI에서 메모 작성 (디버깅용)
bin/sowing memo "테스트 메모입니다"

# DB 마이그레이션
bundle exec rake db:migrate
bundle exec rake db:rollback
bundle exec rake db:reset         # 주의: 인덱스 전체 삭제 (마크다운은 보존)

# 볼트 전체 재인덱싱
bundle exec rake vault:reindex

# 진단 도구
bin/sowing-doctor                 # 환경·볼트·인덱스 상태 점검

# 테스트
bundle exec rspec                            # 전체
bundle exec rspec spec/domain                # 도메인만 (빠름)
bundle exec rspec spec/system                # E2E (느림)
bundle exec rspec spec/compatibility         # 옵시디언 호환성 검증
bundle exec rspec --tag focus                # 집중 실행

# Lint
bundle exec standardrb
bundle exec standardrb --fix

# 패키징
bundle exec rake package:macos
bundle exec rake package:windows
bundle exec rake package:linux
```

---

## 코드 컨벤션

### 명명 규칙

- 모든 클래스: `Sowing::` 네임스페이스 하위.
- **Use Case**: 동사로 시작. `CreateMemo`, `PromoteEntry`, `SearchEntries`. `XxxService` 접미사 금지.
- **Repository**: `Repo` 접미사. `VaultRepo`, `IndexRepo`. `Repository` 풀네임 금지 (긴 줄 회피).
- **Value Object**: 형용사·명사. `Ulid`, `TagSet`, `WikiLink`. `frozen_string_literal: true` + `freeze` 호출 필수.
- **Controller**: `XxxController`, 복수형. `MemosController`, `RecordsController`.
- **파일명**: snake_case. 클래스 이름과 1:1 대응.

### Ruby 스타일

- 모든 파일 첫 줄: `# frozen_string_literal: true`
- 들여쓰기 2 spaces. 하드 탭 금지.
- 한 줄 길이: 120자 권장, 절대 한도 140자.
- `if !` 대신 `unless`, 단 `unless ... else` 금지.
- 가드 클로즈(guard clause) 적극 사용.
- `attr_reader` 우선, 가변 상태 최소화.

### Use Case 작성 패턴

모든 Use Case는 다음 골격을 따른다.

```ruby
# frozen_string_literal: true

module Sowing
  module UseCases
    class CreateMemo
      include Dry::Monads[:result]

      def initialize(vault_repo:, index_repo:, clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @clock = clock
      end

      # @return [Dry::Monads::Result<Domain::Memo, Symbol>]
      def call(body:, tags: [])
        return Failure(:empty_body) if body.to_s.strip.empty?

        memo = Domain::Memo.new(
          id: Domain::Ulid.generate,
          body: body.strip,
          tags: Domain::TagSet.new(tags),
          created_at: @clock.now
        )

        @vault_repo.write(memo)
        @index_repo.upsert(memo)

        Success(memo)
      end
    end
  end
end
```

**Use Case 규칙**:
- 의존성은 keyword argument로 주입 (생성자 DI).
- `call` 메서드 하나만 public. 다른 public 메서드 금지.
- 반환은 항상 `Dry::Monads::Result` (`Success`/`Failure`).
- Sinatra·HTTP를 알면 안 됨.
- 시간이 필요하면 `clock:` 주입 (테스트 가능성).

### Domain 객체 작성 패턴

```ruby
# frozen_string_literal: true

module Sowing
  module Domain
    class Memo
      attr_reader :id, :body, :tags, :created_at

      def initialize(id:, body:, tags:, created_at:)
        @id = id
        @body = body.freeze
        @tags = tags
        @created_at = created_at
        freeze
      end

      def mode
        :memo
      end

      def to_frontmatter
        {
          "id" => id.to_s,
          "mode" => mode.to_s,
          "created_at" => created_at.iso8601,
          "updated_at" => created_at.iso8601,
          "tags" => tags.to_a
        }
      end
    end
  end
end
```

**Domain 규칙**:
- 불변(immutable). `freeze` 호출 필수.
- 외부 의존 금지 (Sequel·Sinatra·File 등).
- 단위 테스트는 stub/mock 없이 순수하게 작성 가능해야 함.

### 파일 쓰기 규칙

직접 `File.write` 금지. 반드시 SafeWriter 사용:

```ruby
# 올바름
@safe_writer.atomic_write(path, content)

# 금지
File.write(path, content)         # ❌
File.open(path, "w") { ... }      # ❌
```

이유: 쓰기 도중 강제 종료되어도 파일이 깨지지 않도록 임시 파일 + rename(원자적 교체) 패턴을 강제.

### 검증

사용자 입력 검증은 dry-validation 컨트랙트로:

```ruby
class MemoContract < Dry::Validation::Contract
  params do
    required(:body).filled(:string, max_size?: 10_000)
    optional(:tags).array(:string)
  end
end
```

컨트롤러에서 `result = MemoContract.new.call(params)` 호출 후 분기.

---

## 절대 하지 말 것 (Anti-patterns)

- ❌ ActiveRecord 사용 (Sequel만)
- ❌ React/Vue/Svelte 도입 (Hotwire만)
- ❌ Webpack/Vite/Rollup 등 JS 빌드 도구 도입
- ❌ Redis·Sidekiq 등 외부 인프라 의존
- ❌ Domain 객체가 DB·HTTP·File 직접 참조
- ❌ Use Case가 다른 Use Case 호출 (Composition 필요하면 새 Use Case 작성)
- ❌ Controller에 비즈니스 로직 (Use Case로 위임)
- ❌ `File.write` 직접 호출 (SafeWriter 사용)
- ❌ raw SQL을 컨트롤러·Use Case에 작성 (Repository 안에만)
- ❌ frontmatter에 한국어 키 사용 (옵시디언 호환성, 영문 snake_case)
- ❌ `puts` 디버깅 (커밋 전 `Sowing.logger`로 대체)
- ❌ 텔레메트리·analytics·crash report (사용자 동의 없는 외부 통신)
- ❌ 사용자 파일 영구 삭제 (휴지통 이동만)

---

## 테스트 작성 규칙

### 테스트 종류와 위치

| 종류 | 위치 | 도구 | 속도 목표 |
|------|------|------|-----------|
| Domain | `spec/domain/` | RSpec | 100건 < 1초 |
| Use Case | `spec/use_cases/` | RSpec + 인메모리 fake repo | 100건 < 5초 |
| Repository | `spec/repositories/` | RSpec + 임시 디렉토리 | 50건 < 10초 |
| System (E2E) | `spec/system/` | Capybara + Rack::Test | 30건 < 60초 |
| Compatibility | `spec/compatibility/` | RSpec + 픽스처 볼트 | 20건 < 30초 |
| Chaos | `spec/chaos/` | RSpec + 강제 종료 시뮬레이션 | 10건 < 60초 |

### 신규 Use Case PR 체크리스트

새 Use Case를 추가하면 항상 다음 테스트가 함께 와야 한다:

- [ ] 정상 경로 (Success)
- [ ] 입력 검증 실패 (Failure 적어도 1종)
- [ ] 외부 시스템 실패 시 동작 (예: 디스크 가득)
- [ ] 멱등성 (있다면)

### 테스트는 한국어로 작성

```ruby
RSpec.describe Sowing::UseCases::CreateMemo do
  describe "#call" do
    context "정상 입력일 때" do
      it "메모를 볼트에 저장하고 인덱스를 갱신한다" do
        # ...
      end
    end

    context "본문이 비어있을 때" do
      it ":empty_body 실패를 반환한다" do
        # ...
      end
    end
  end
end
```

이유: 도메인 언어가 한국어이므로 테스트도 도메인 언어로 작성하는 것이 명세 가독성에 유리.

---

## 옵시디언 호환성 체크리스트

마크다운을 다루는 코드를 작성·수정할 때마다 다음을 자문할 것:

- [ ] 생성된 frontmatter가 valid YAML인가?
- [ ] 옵시디언이 인식하는 표준 키만 사용하나? (`tags`, `aliases`, `cssclasses` 등)
- [ ] 한글이 포함된 파일명이 NFC 정규화 되어 있나? (특히 macOS↔Windows)
- [ ] 위키링크 `[[]]` 안에 옵시디언이 깨뜨리는 문자(`|`, `#`, `^`)가 escape 되어 있나?
- [ ] `.sowing/` 외 폴더에 자체 메타파일(`.sowing-state.json` 등)을 흩뿌리지 않나?
- [ ] 본문에 본 앱만의 magic comment 도입을 피했나?

수정 시 `bundle exec rspec spec/compatibility` 통과 확인 필수.

---

## 새 기능 추가 워크플로우

Claude Code가 신규 기능을 구현할 때 따라야 할 표준 절차:

1. **명세 확인**: `docs/SPEC.md`에서 해당 기능 항목 확인. 없으면 사용자에게 질문.
2. **결정 기록 검토**: `docs/DECISIONS.md`에서 관련 결정 검토.
3. **로드맵 위치 확인**: `ROADMAP.md`에서 해당 기능이 어느 phase에 속하는지 확인. Phase 외 기능 구현 전 사용자 확인.
4. **도메인부터 작성**: Domain 객체 → 단위 테스트 → Use Case → Use Case 테스트 → Repository → Controller → 뷰 순서.
5. **호환성 테스트**: 마크다운/볼트 관련 변경이면 `spec/compatibility` 갱신.
6. **수동 검증 시나리오**: PR 설명에 옵시디언과 본 앱 양쪽에서 검증한 시나리오 기재.

---

## 디렉토리 구조 빠른 참조

```
sowing/
├── CLAUDE.md                    # ★ 본 파일
├── README.md
├── SETUP.md                     # 개발환경 설정
├── ROADMAP.md                   # 8주 일정 + 세부 작업
├── docs/
│   ├── SPEC.md                  # 전체 명세
│   └── DECISIONS.md             # 아키텍처 의사결정 (ADR)
├── bin/
│   ├── sowing                   # 메인 실행
│   └── sowing-doctor            # 진단
├── config/
│   ├── application.rb
│   ├── routes.rb
│   └── locales/ko.yml
├── lib/sowing/
│   ├── domain/                  # 외부 의존 0
│   ├── use_cases/               # 비즈니스 로직
│   ├── repositories/            # 영속성
│   ├── infrastructure/          # 어댑터
│   ├── controllers/             # Sinatra
│   └── helpers/
├── views/                       # ERB
├── public/                      # 정적 자원 (CDN 우선, 최소화)
├── templates/                   # 12종 교사 템플릿 (.md)
├── db/migrations/
├── spec/
└── packaging/
```

---

## 환경 변수

| 이름 | 기본값 | 설명 |
|------|--------|------|
| `SOWING_ENV` | `development` | `development` / `test` / `production` |
| `SOWING_VAULT` | `~/Documents/SowingVault` | 볼트 위치. CLI/UI에서 override 가능 |
| `SOWING_DATA_DIR` | OS별 표준 위치 | SQLite·로그 저장 위치 |
| `SOWING_PORT` | `48723` | 로컬 서버 포트 |
| `SOWING_LOG_LEVEL` | `info` | `debug` / `info` / `warn` / `error` |

OS별 기본 데이터 디렉토리:
- macOS: `~/Library/Application Support/Sowing/`
- Windows: `%APPDATA%\Sowing\`
- Linux: `~/.local/share/sowing/` (XDG 준수)

---

## Claude Code 작업 시 추가 주의사항

- **사용자 데이터를 만지는 작업은 항상 두 번 묻는다.** 마이그레이션·재인덱싱·삭제는 dry-run 모드를 항상 먼저 제공.
- **로케일은 한국어가 기본**이다. 새 UI 문구는 `config/locales/ko.yml`에 추가하고, 코드에서 `t(".key")` 호출.
- **시간대는 항상 사용자 로컬**이다. `Time.now.iso8601`이 아닌 `Time.now.iso8601`로 시간대 포함 저장. UTC 강제 변환 금지.
- **에러 메시지는 사용자 액션을 명시한다.** "Failed to write" ❌ → "메모 저장에 실패했습니다. 디스크 여유 공간을 확인해 주세요." ✅
- **변경 후 항상 테스트 실행.** `bundle exec rspec` 실행 결과를 PR 설명에 포함.
- **본 문서를 갱신해야 할 새 컨벤션이 생기면 즉시 갱신**한다. CLAUDE.md는 살아있는 문서다.

---

마지막 갱신: 2026-05-07
