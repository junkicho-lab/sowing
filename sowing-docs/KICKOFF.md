# 착수 가이드 (KICKOFF)

이 문서는 **본 프로젝트를 처음 받은 엔지니어 (또는 Claude Code) 가 첫 한 시간을 어떻게 써야 하는지** 안내합니다.

---

## 0. 본 패키지 안에 무엇이 있나

```
sowing/
├── README.md              # 공개 프로젝트 개요
├── KICKOFF.md             # ★ 본 파일 — 첫 한 시간 안내
├── CLAUDE.md              # ★ Claude Code 운영 매뉴얼
├── SETUP.md               # 개발 환경 설정 단계별
├── ROADMAP.md             # 8주 MVP 작업 분해 (작업 ID 부여됨)
├── docs/
│   ├── SPEC.md            # 전체 기술 명세서 (1100+ 줄)
│   └── DECISIONS.md       # 아키텍처 의사결정 기록 (ADR 10건)
├── Gemfile                # 의존성 (검증 완료)
├── Rakefile, config.ru
├── .ruby-version, .gitignore, .rspec, .standard.yml
├── bin/sowing             # CLI 진입점 (서브커맨드 골격)
├── bin/sowing-doctor      # 진단 도구
├── config/
│   ├── application.rb     # 앱 부트스트랩 + Sinatra 베이스
│   ├── routes.rb          # 라우트 (현재 / 와 /health 만)
│   └── locales/ko.yml     # 한국어 로케일 골격
├── lib/sowing/
│   ├── version.rb
│   └── infrastructure/
│       ├── paths.rb       # OS별 경로 결정 (구현 완료)
│       └── db.rb          # SQLite 연결 (구현 완료)
├── db/migrations/
│   └── 001_create_entries.rb  # entries 테이블 (적용 가능)
├── spec/
│   ├── spec_helper.rb     # RSpec 설정 (격리된 임시 볼트)
│   └── sowing_spec.rb     # 첫 샘플 테스트
├── templates/
│   └── lesson_reflection.md  # 1번째 교사 템플릿 (참조용)
└── packaging/             # (Week 8에 채워짐)
```

**구현 완료**: Paths, DB 연결, CLI 골격, 마이그레이션 1개, 첫 테스트
**미구현**: 도메인 객체, Use Case, Repository, Controller, View, 나머지 11개 템플릿

---

## 1. 첫 한 시간 체크리스트

### Step 1 — 문서 읽기 (15분)

다음 순서로 읽으세요. **순서가 중요합니다.**

1. **`README.md`** — 5분. 무엇을 만드는지 한 번에 파악.
2. **`docs/SPEC.md` §3 핵심 개념 모델** — 5분. 메모/필기/기록 3축. 다른 모든 결정의 뿌리.
3. **`docs/DECISIONS.md` ADR-001, 002, 003, 004, 005, 006** — 5분. 사용자가 확정한 핵심 결정.

이 3개만 먼저 읽으세요. 나머지는 작업하면서 필요할 때.

### Step 2 — 환경 구축 (20분)

`SETUP.md` 1~5번 따라하기:
1. Ruby 3.3.0 설치
2. `bundle install`
3. `bundle exec rake db:setup`
4. `bin/sowing dev`
5. 브라우저에서 `http://127.0.0.1:48723` 확인 ("Hello, Sowing 🌱" 표시)

`bundle exec rspec` 실행해서 샘플 테스트가 통과하는지 확인.

### Step 3 — 첫 작업 선택 (10분)

`ROADMAP.md` 의 **W1-T01** 부터 순서대로.

실제로 W1-T01은 본 패키지에서 이미 일부 구현되어 있습니다 (Gemfile, Rakefile, config 등). 검증·보완이 첫 작업입니다:

```bash
claude "ROADMAP.md의 W1-T01을 검증해줘. 이미 만들어진 부분을 확인하고 누락된 게 있으면 채워줘. 마지막으로 bin/sowing dev 가 동작하고 bundle exec rspec 가 통과하는지 확인해."
```

### Step 4 — Claude Code 첫 호출 (15분)

W1-T04 부터는 새로 만드는 작업입니다. 다음과 같이 호출하세요:

```bash
claude "W1-T04 작업을 진행해줘. CLAUDE.md의 도메인 객체 작성 패턴을 따르고, 작업 끝나면 spec 통과 결과를 보여줘."
```

Claude Code는 자동으로 `CLAUDE.md` 와 `ROADMAP.md` 를 참조합니다.

---

## 2. 첫 주에 만들 것 (Week 1 마일스톤)

```
✅ CLI에서 메모를 만들고, 옵시디언으로 열어볼 수 있다.
```

이게 끝나면 본 프로젝트의 핵심 가치 명제(옵시디언 호환 마크다운 자동 생성) 가 검증됩니다.

작업 순서:
1. W1-T01 ~ T03 (이미 일부 완료): 환경·DB·로깅
2. W1-T04: Ulid, TagSet (1~2시간)
3. W1-T05: Memo, Note, Record 도메인 객체 (반나절)
4. W1-T06: VaultRepo (반나절 — 가장 까다로움)
5. W1-T07: IndexRepo (반나절)
6. W1-T08: CreateMemo Use Case + CLI (1~2시간)

검증 시나리오:
```bash
bin/sowing memo "오늘 1교시 수업이 활기찼다"
ls $SOWING_VAULT/00_Inbox/
cat $SOWING_VAULT/00_Inbox/2026-*.md
# → frontmatter + 본문이 있어야 함

# 옵시디언으로 $SOWING_VAULT 를 열어 동일 파일 확인
```

---

## 3. Claude Code 활용 팁

### 한 작업씩 명확히 지시

❌ 좋지 않은 지시: "메모 기능 만들어줘"
✅ 좋은 지시: "ROADMAP.md의 W1-T08 작업을 진행해줘. 검증 항목까지 모두 통과하면 PR 메시지 초안을 한국어로 만들어줘"

### 자주 하는 작업

```bash
# 작업 진행
claude "W2-T05 진행"

# 작업 후 검증
claude "방금 만든 NotesController의 spec을 보강해줘"

# 옵시디언 호환성 점검
claude "방금 변경한 코드가 옵시디언 호환성을 깨지 않는지 확인하고 spec/compatibility 에 케이스를 추가해줘"

# 새 ADR 추가
claude "Sequel ORM 마이그레이션 컨벤션에 대한 ADR을 docs/DECISIONS.md 에 추가해줘. ADR-011 번호 사용"

# 진행 상황 업데이트
claude "ROADMAP.md 에서 W1 작업들을 완료 표시로 갱신해줘"
```

### 위험한 작업은 dry-run 먼저

```bash
claude "vault:reindex 작업을 만드는데, 먼저 dry-run 모드를 만들고 그게 검증되면 실제 모드를 추가해줘"
```

---

## 4. 의사결정이 필요할 때

다음 상황에서는 **사용자에게 먼저 확인**하세요 (Claude Code도 마찬가지):

- 기술 스택 변경 (Sequel → ActiveRecord, Sinatra → Rails 등)
- 외부 네트워크 호출 추가
- 사용자 데이터 형식 변경
- 의존성 gem 추가
- ROADMAP.md 의 작업 범위·순서 변경
- ADR 작성

확인 후 결정사항은 `docs/DECISIONS.md` 에 ADR로 추가합니다.

---

## 5. 일일 작업 종료 체크리스트

매일 작업을 마치기 전:

- [ ] `bundle exec rspec` 전체 통과
- [ ] `bundle exec standardrb` 통과
- [ ] `ROADMAP.md` 의 작업 상태 갱신
- [ ] 본일 변경된 파일 commit (작업 ID prefix: `[W2-T05] ...`)
- [ ] 새로 발견한 작업이나 결정이 있다면 문서에 반영

---

## 6. 막혔을 때

- **명세 모호**: `docs/SPEC.md` 검색 → 없으면 사용자 확인
- **기술 결정 필요**: `docs/DECISIONS.md` 검색 → 없으면 ADR 작성 후 사용자 확인
- **스택 사용법 모름**: 외부 문서 참조 (`docs/SPEC.md` §17.2 참고 자료)
- **어디서 시작할지 모름**: 본 문서 §2 다시 읽기

---

## 7. 본 프로젝트의 영혼

기능을 빠르게 쌓는 것보다 **본 프로젝트의 핵심 가치 두 가지**를 지키는 것이 중요합니다:

1. **옵시디언 호환성**: 이게 깨지는 순간 본 프로젝트의 존재 이유가 사라집니다.
2. **사용자 데이터 안전**: 한 번이라도 데이터를 잃게 만들면 신뢰가 무너집니다.

기능 1개 늦게 만드는 것보다, 데이터 1건 잃지 않는 것이 100배 중요합니다.

---

행운을 빕니다 🌱

— 2026-05-07
