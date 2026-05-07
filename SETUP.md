# 개발 환경 설정 가이드

본 문서는 Sowing 개발 환경을 처음 구축하는 엔지니어를 위한 단계별 가이드입니다.

대상: 처음 본 저장소를 클론한 엔지니어
예상 소요 시간: 30분 ~ 1시간

---

## 1. 사전 요구사항

### 1.1 OS

다음 OS 중 하나에서 개발 가능합니다.
- macOS 13 (Ventura) 이상
- Ubuntu 22.04 이상
- Windows 11 + WSL2 (네이티브 Windows 개발은 패키징 단계에서만 권장)

### 1.2 필수 도구

```bash
# 버전 확인
ruby --version       # 3.3.x
bundler --version    # 2.5.x 이상
sqlite3 --version    # 3.45.x 이상
git --version        # 2.40 이상
```

### 1.3 권장 도구

- **Ruby 버전 관리**: rbenv 또는 mise (asdf)
- **에디터**: VS Code + Ruby LSP / RubyMine / Neovim
- **DB 탐색**: TablePlus, DBeaver, 또는 `sqlite3` CLI
- **옵시디언**: 호환성 검증을 위해 [obsidian.md](https://obsidian.md) 설치

---

## 2. Ruby 설치

### macOS (rbenv 사용)

```bash
brew install rbenv ruby-build
rbenv install 3.3.0
rbenv global 3.3.0
```

### Ubuntu

```bash
sudo apt update
sudo apt install -y libssl-dev libreadline-dev zlib1g-dev libsqlite3-dev \
                    build-essential libyaml-dev libffi-dev

# rbenv 설치
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

rbenv install 3.3.0
rbenv global 3.3.0
```

### Windows (WSL2)

WSL2 Ubuntu 환경에서 위 Ubuntu 절차를 따르세요.

---

## 3. 저장소 클론 및 의존성 설치

```bash
git clone <repository-url> sowing
cd sowing

# Ruby 버전 확인
cat .ruby-version              # 3.3.0

# 의존성 설치
bundle install

# DB 초기화
bundle exec rake db:setup
```

`db:setup`는 다음을 수행합니다:
- 데이터 디렉토리 생성 (`~/Library/Application Support/Sowing/` 또는 OS별 경로)
- SQLite 데이터베이스 파일 생성
- 모든 마이그레이션 적용

---

## 4. 개발용 볼트 준비

개발 중에는 사용자 볼트와 격리된 별도의 테스트 볼트를 사용합니다.

```bash
# 환경 변수 설정 (셸 rc 파일에 추가 권장)
export SOWING_ENV=development
export SOWING_VAULT=$HOME/SowingDevVault

# 첫 실행 시 자동으로 디렉토리 생성됨
mkdir -p $SOWING_VAULT
```

샘플 콘텐츠를 미리 채우려면:

```bash
bundle exec rake vault:seed
```

이 명령은 `db/seeds/` 의 샘플 메모·필기·기록을 볼트에 복사합니다.

---

## 5. 개발 서버 실행

```bash
bin/sowing dev
```

- 브라우저가 자동으로 `http://127.0.0.1:48723` 을 엽니다.
- 코드 변경 시 자동 재시작 (`rerun` gem).
- 로그는 콘솔에 실시간 출력.

종료: `Ctrl+C`

---

## 6. 첫 작업 검증

다음 시나리오가 정상 동작하는지 확인합니다.

1. 브라우저에서 대시보드 화면이 보인다
2. 우상단 "+ 빠른 메모" 버튼 클릭 → 메모 모달이 뜬다
3. "테스트 메모입니다" 입력 후 `⌘+Enter` (Mac) 또는 `Ctrl+Enter` (Win/Linux) → 저장됨
4. 터미널에서 다음 확인:
   ```bash
   ls $SOWING_VAULT/00_Inbox/
   # 2026-05-07_HHmmss.md 형식의 파일이 보여야 함

   cat $SOWING_VAULT/00_Inbox/*.md
   # frontmatter + 본문이 올바른 형식인지 확인
   ```
5. 옵시디언으로 `$SOWING_VAULT` 를 열어 동일 파일이 정상 표시되는지 확인

---

## 7. 테스트 실행

```bash
# 전체 테스트
bundle exec rspec

# 빠른 단위 테스트만
bundle exec rspec spec/domain spec/use_cases

# 옵시디언 호환성 테스트
bundle exec rspec spec/compatibility

# 특정 파일
bundle exec rspec spec/use_cases/create_memo_spec.rb

# 라인 번호로 특정 테스트
bundle exec rspec spec/use_cases/create_memo_spec.rb:42
```

테스트 실행 시 별도의 임시 볼트가 자동 생성됩니다 (`/tmp/sowing-test-*`). 사용자 볼트에 영향 없음.

---

## 8. Lint 및 포매팅

```bash
# 검사
bundle exec standardrb

# 자동 수정
bundle exec standardrb --fix
```

커밋 전 `standardrb` 통과 필수. CI에서 강제됩니다.

---

## 9. Claude Code 사용

Claude Code를 본 저장소에서 사용하면 자동으로 [`CLAUDE.md`](CLAUDE.md) 의 컨벤션을 따릅니다.

권장 워크플로우:

```bash
# 저장소 루트에서 실행
claude

# 또는 특정 작업 명세
claude "ROADMAP.md의 W2-T03 작업을 구현해줘"
```

Claude Code 작업 시작 전 다음을 확인하세요:
- 현재 git 브랜치가 작업용 브랜치인가
- 최신 main을 pull 받았는가
- `bundle install` 했는가

---

## 10. 자주 발생하는 문제

### `sqlite3` gem 설치 실패 (macOS)

```bash
brew install sqlite3
bundle config build.sqlite3 --with-sqlite3-dir=$(brew --prefix sqlite3)
bundle install
```

### `listen` gem이 파일 변경을 감지하지 못함 (Linux)

inotify 한도 부족일 수 있습니다.

```bash
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 포트 48723이 이미 사용 중

```bash
SOWING_PORT=48724 bin/sowing dev
```

### 한글 파일명 깨짐 (macOS↔Linux)

NFC 정규화 문제입니다. `bin/sowing-doctor` 실행 후 안내를 따르세요.

### Tebako 패키징 실패

Tebako는 Docker 기반으로 동작합니다. Docker Desktop이 실행 중인지 확인하세요. 자세한 안내는 [`packaging/README.md`](packaging/README.md) 참조.

---

## 11. 다음 단계

설정이 끝났다면:

1. [`CLAUDE.md`](CLAUDE.md) 를 읽고 코드 컨벤션을 숙지하세요.
2. [`docs/SPEC.md`](docs/SPEC.md) 의 §3 (핵심 개념 모델) 을 반드시 읽으세요.
3. [`ROADMAP.md`](ROADMAP.md) 에서 첫 작업을 고르세요.

질문은 GitHub Issues로 부탁드립니다.
