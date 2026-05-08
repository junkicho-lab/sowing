# Sowing 패키징 (W8)

3개 OS(macOS / Linux / Windows)용 단일 실행 파일 빌드 + 인스톨러 제작.

## 진행 상태

| 작업 | 상태 | 비고 |
|------|------|------|
| W8-T02 Tebako 빌드 검증 | 🟡 스캐폴드 | 실제 빌드는 Tebako 바이너리 + Docker 필요 |
| W8-T03 macOS DMG + codesign + notarize | ⏳ Deferred | Apple Developer 계정·인증서 필요 |
| W8-T04 Windows Inno Setup | ⏳ Deferred | Windows VM/머신 + Inno Setup 필요 |
| W8-T05 Linux AppImage | ⏳ Deferred | linuxdeploy 설치 + 실제 환경 검증 필요 |
| W8-T01 시스템 트레이 wrapper | ⏳ Deferred | OS별 native 코드 (Swift / WPF / GTK) |

## 빠른 빌드

```sh
./packaging/build.sh              # 현재 OS
./packaging/build.sh linux        # Linux x86_64 (Docker 필요)
./packaging/build.sh all          # 지원 OS 모두
```

산출물: `dist/sowing-{VERSION}-{OS}-{ARCH}[.exe]`

## 사전 요구사항

### Linux 빌드 (Docker 사용)
```sh
docker pull ghcr.io/tamatebako/tebako:latest
```

### macOS 빌드 (호스트 직접)
```sh
brew install tebako   # 정식 배포되면. 현재는 source build 필요할 수 있음.
```

### Windows 빌드
GitHub Actions의 `windows-latest` runner에서 진행 권장.
또는 로컬 Windows + WSL2에 Tebako 설치.

## 추가 단계 (출시 전)

### macOS (T03)
1. Apple Developer 인증서 등록 (`Developer ID Application`)
2. `packaging/macos/build.sh` 작성 — codesign + notarize + DMG 생성
3. Gatekeeper 통과 확인 (`spctl -a -v dist/Sowing.app`)

### Windows (T04)
1. [Inno Setup](https://jrsoftware.org/isinfo.php) 설치
2. `packaging/windows/installer.iss` 작성 — 단일 EXE → 인스톨러
3. 코드 사이닝 (선택, Authenticode 인증서 필요)

### Linux (T05)
1. AppImage 도구 설치: `linuxdeploy`, `appimagetool`
2. `packaging/linux/build.sh` 작성 — 바이너리 + .desktop + 아이콘 → AppImage
3. 우분투 22.04에서 더블클릭 실행 검증

## 시스템 트레이 (T01, 선택)

비-필수. CLI/웹 UI만으로 MVP 충족. 추가 시:
- macOS: SwiftUI MenuBarExtra 또는 platypus
- Windows: WPF NotifyIcon
- Linux: AppIndicator (Ubuntu) 또는 Tray (다른 DE)

각 OS wrapper는 백그라운드에서 `bin/sowing start` 를 실행하고
메뉴에서 "빠른 메모", "대시보드", "종료" 액션 제공.
