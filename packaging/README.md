# Sowing 패키징 — 현재 상태 매트릭스

| 설치 경로 | 상태 | 외부 리소스 필요 | 출처 |
|-----------|------|------------------|------|
| **Docker** (가장 빠름) | ✅ 완료 | Docker Desktop | `Dockerfile` + `docker-compose.yml` |
| **bin/sowing-install 스크립트** (curl 한 줄) | ✅ 완료 | Ruby 3.3+ | `bin/sowing-install` |
| **소스 직접** (`git clone` + `bundle install`) | ✅ 완료 | Ruby 3.3+ | `SETUP.md` |
| **Homebrew Tap** (macOS) | 🟡 Formula 작성, Tap 저장소 별도 필요 | 없음 (Apple Dev 불필요) | `packaging/homebrew/sowing.rb` |
| **GitHub Actions CI 빌드** | ✅ 완료 | 없음 (GitHub-provided runner) | `.github/workflows/build.yml` |
| **macOS DMG (codesign + notarize)** | ⏳ Deferred | Apple Developer 계정 ($99/년) | `packaging/macos/build.sh` (작성 대기) |
| **Windows Inno Setup** | ⏳ Deferred | Windows VM + Inno Setup | `packaging/windows/installer.iss` (작성 대기) |
| **Linux AppImage** | ⏳ Deferred | linuxdeploy + 실 환경 | `packaging/linux/build.sh` (작성 대기) |
| **Tebako 단일 바이너리** | 🟡 스캐폴드 | Tebako 빌드 환경 | `packaging/build.sh` + `packaging/tebako.yml` |
| **시스템 트레이 wrapper** | ⏳ Deferred | OS 별 native 코드 | — |

## 즉시 가능한 4 설치 경로

### 1. Docker (5초 셋업, 가장 권장)

```sh
git clone https://github.com/junkicho-lab/sowing.git
cd sowing
docker compose up -d
# 브라우저: http://127.0.0.1:48723
```

vault 는 호스트의 `./vault/` 폴더에 생성. 다른 위치를 쓰려면:
```sh
SOWING_VAULT_HOST=~/Documents/MyVault docker compose up -d
```

### 2. 한 줄 설치 스크립트 (Ruby 3.3+ 있는 환경)

```sh
curl -fsSL https://raw.githubusercontent.com/junkicho-lab/sowing/main/bin/sowing-install | bash
```

자동으로:
- OS 탐지 (macOS / Linux)
- Ruby 3.3+ 검증
- 저장소 clone (`~/.sowing/app`)
- bundle install + db:setup
- `bin/sowing-doctor` 진단 + 첫 실행 안내

### 3. 소스 직접 (개발자)

```sh
git clone https://github.com/junkicho-lab/sowing.git
cd sowing
bundle install
bundle exec rake db:setup
bin/sowing dev
```

자세한 셋업: [SETUP.md](../SETUP.md)

### 4. Homebrew Tap (macOS, Tap 저장소 게시 후 사용 가능)

```sh
brew tap junkicho-lab/sowing
brew install sowing
```

Tap 저장소 (`homebrew-sowing`) 운영자가 별도 생성 필요. Formula 는
`packaging/homebrew/sowing.rb` 그대로 복사.

## 빌드 검증 — GitHub Actions

`.github/workflows/build.yml` 가 매 push/PR 마다 자동 실행:
- macOS / Ubuntu / Windows runner 에서 `bundle install + spec + lint + doctor`
- Docker 이미지 빌드 + healthcheck
- 각 OS 별 source ZIP artifact 14일 보관

CI 통과만으로 "이 commit 은 3 OS 에서 동작한다" 확인 가능.

## 정식 release (signing/notarization 필요한 작업)

각 OS 별 정식 인스톨러는 외부 리소스 필요해 deferred. 작업 진입 시:

### macOS (W8-T03)
1. Apple Developer 인증서 등록 (`Developer ID Application`)
2. `packaging/macos/build.sh` 작성 — codesign + notarize + DMG
3. Gatekeeper 통과 확인 (`spctl -a -v dist/Sowing.app`)
4. `.github/workflows/release.yml` 에 macos artifact + signing step 추가

### Windows (W8-T04)
1. [Inno Setup](https://jrsoftware.org/isinfo.php) 설치
2. `packaging/windows/installer.iss` 작성 — 단일 EXE → 인스톨러
3. 코드 사이닝 (선택, Authenticode 인증서)

### Linux (W8-T05)
1. AppImage 도구: `linuxdeploy`, `appimagetool`
2. `packaging/linux/build.sh` — 바이너리 + `.desktop` + 아이콘 → AppImage
3. 우분투 22.04 더블클릭 실행 검증

### 시스템 트레이 (W8-T01, 선택)
- macOS: SwiftUI MenuBarExtra 또는 Platypus
- Windows: WPF NotifyIcon
- Linux: AppIndicator (Ubuntu) 또는 Tray

각 OS wrapper 는 백그라운드에서 `bin/sowing start` 실행, 메뉴에서
"빠른 메모"·"대시보드"·"종료" 액션 제공.

## Tebako 단일 바이너리 (대안)

Ruby 인터프리터 + 의존성 + 소스를 단일 실행 파일로 묶음.
사용자는 Ruby 설치 불필요.

```sh
./packaging/build.sh              # 현재 OS
./packaging/build.sh linux        # Linux x86_64 (Docker 필요)
./packaging/build.sh all          # 지원 OS 모두
```

산출물: `dist/sowing-{VERSION}-{OS}-{ARCH}[.exe]`

자세한 사전 요구사항은 [tebako.yml](tebako.yml) 참조.
