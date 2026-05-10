# Sowing macOS DMG 빌드

Apple Developer 계정 *없이도* 동작하는 unsigned DMG 빌더.
정식 codesign + notarize 는 환경 변수 설정 시 자동 추가.

## 빠른 빌드 (로컬)

```sh
./packaging/macos/build.sh
# 산출물: dist/Sowing-{VERSION}.dmg + .sha256
```

자동:
- Info.plist 버전 치환
- launcher.sh → MacOS/Sowing
- 소스 복사 (`Resources/sowing/` 안에 `lib/`, `views/`, `Gemfile` 등)
- DMG 스테이징 (Sowing.app + Applications symlink + 안내 텍스트)
- hdiutil UDZO 압축 + SHA256 체크섬

## 사용자 경험 (unsigned DMG)

1. DMG 더블클릭 → 마운트
2. `Sowing.app` 을 Applications 폴더로 드래그
3. Applications 에서 `Sowing` 더블클릭
   - **Gatekeeper 경고**: 우클릭 → 열기 → 열기 (한 번만)
   - 또는: `xattr -dr com.apple.quarantine /Applications/Sowing.app`
4. Terminal 창이 자동 열리면서:
   - 첫 실행: `bundle install + db:setup` (1~2분)
   - 이후: dev 서버 시작 + 브라우저 자동 open `http://127.0.0.1:48723`
5. 종료: Terminal 창 닫기 또는 `⌃C`

DMG 안의 `먼저 읽어주세요.txt` 가 Gatekeeper 우회 방법 안내.

## Ruby 의존성

`.app` 자체는 Ruby 를 번들하지 *않음* — macOS 시스템 Ruby (14.4+) 또는
Homebrew Ruby 자동 탐지. Ruby 없거나 3.3 미만이면 `osascript` 다이얼로그
+ SETUP.md 안내.

> **개선 옵션**: Tebako 로 Ruby + 의존성 모두 .app 안에 번들 → Ruby 설치 불필요.
> `packaging/build.sh macos` (W8-T02) 참조 — 현재는 Tebako 환경 별도 셋업 필요.

## 정식 release (Apple Developer 계정 확보 시)

### 1. 인증서 등록

Apple Developer 포털 → Certificates → Developer ID Application 발급 →
keychain 등록. 인증서 이름 확인:

```sh
security find-identity -p codesigning -v | grep "Developer ID Application"
```

### 2. codesign + notarize 환경 변수

```sh
# ~/.zshrc 또는 빌드 환경에 설정
export SOWING_CODESIGN_IDENTITY="Developer ID Application: 본인이름 (TEAM_ID)"

# notarize: notarytool keychain-profile 미리 등록
xcrun notarytool store-credentials sowing-notarize \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password"
export SOWING_NOTARIZE_PROFILE="sowing-notarize"
```

### 3. 빌드 (자동으로 codesign + notarize 진행)

```sh
./packaging/macos/build.sh
```

`build.sh` 가 자동으로:
- `codesign --force --deep --sign "$IDENTITY" --options runtime --timestamp` 적용
- `xcrun notarytool submit ... --wait` 으로 Apple 검증
- `xcrun stapler staple` 로 noterize 결과 DMG 에 부착

### 4. 검증

```sh
spctl -a -v dist/build/Sowing.app           # accepted (signed by ...)
stapler validate dist/Sowing-*.dmg          # 검증 OK
```

## CI 빌드 (GitHub Actions)

`.github/workflows/release-macos.yml` 가 v 태그 push 시 자동 진행.
현재는 unsigned DMG 만 빌드. signing/notarization 추가 시 secrets 등록:

- `MACOS_CERT_BASE64` — `Developer ID Application` p12 base64
- `MACOS_CERT_PASSWORD` — p12 비밀번호
- `MACOS_NOTARY_PROFILE_*` — Apple ID, team ID, app password

## 아이콘

`Sowing.icns` — 1024x1024 ~ 16x16 multi-res ICNS 권장.
없으면 빈 placeholder. 실 출시 전 디자이너 작업 권장:

```sh
# PNG → ICNS (mkbundle 도구)
mkdir Sowing.iconset
sips -z 16 16     icon.png --out Sowing.iconset/icon_16x16.png
sips -z 32 32     icon.png --out Sowing.iconset/icon_16x16@2x.png
# ... (16, 32, 64, 128, 256, 512, 1024)
iconutil -c icns Sowing.iconset
mv Sowing.icns packaging/macos/Sowing.icns
```

## TODO (W8-T03 정식 완료 시)

- [ ] Apple Developer 계정 등록 ($99/년)
- [ ] Developer ID Application 인증서 발급 + keychain 등록
- [ ] notarytool keychain-profile 등록
- [ ] `Sowing.icns` 디자인 + 다중 해상도 (1024 ~ 16)
- [ ] CI secrets 등록 (`MACOS_CERT_*`, `MACOS_NOTARY_*`)
- [ ] release-macos.yml workflow 의 codesign/notarize step 활성화
- [ ] 첫 정식 signed release 검증 (Mac App Store 가 아닌 Developer ID 배포)
