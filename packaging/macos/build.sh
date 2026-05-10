#!/usr/bin/env bash
# Sowing macOS DMG 빌더 (W8-T03 부분 — unsigned).
#
# 입력: 이 저장소 (./)
# 출력: dist/Sowing-{VERSION}.dmg
#
# 동작:
#   1. dist/build/Sowing.app/ 번들 조립
#      - Contents/Info.plist (버전 치환)
#      - Contents/MacOS/Sowing (launcher.sh)
#      - Contents/Resources/sowing/ (Ruby 소스 — bundle install 안 함, 첫 실행 시 .app 가 진행)
#      - Contents/Resources/Sowing.icns (아이콘 — 없으면 빈 placeholder)
#   2. (선택) codesign — 환경 변수 SOWING_CODESIGN_IDENTITY 있을 때만
#   3. DMG 조립
#      - 스테이징 폴더: Sowing.app + Applications symlink + README.txt
#      - hdiutil create UDZO 압축
#   4. (선택) notarize — 환경 변수 SOWING_NOTARIZE_PROFILE 있을 때만
#
# 사용:
#   ./packaging/macos/build.sh
#   SOWING_CODESIGN_IDENTITY="Developer ID Application: ..." ./packaging/macos/build.sh
#
# 사전 요구사항: macOS, hdiutil (built-in)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ 이 스크립트는 macOS 에서만 동작합니다."
  exit 1
fi

VERSION="$(ruby -r ./lib/sowing/version -e 'print Sowing::VERSION')"
DIST="$ROOT/dist"
BUILD="$DIST/build"
APP_NAME="Sowing.app"
APP="$BUILD/$APP_NAME"
DMG_STAGE="$BUILD/dmg-stage"
DMG_OUT="$DIST/Sowing-${VERSION}.dmg"
PACKAGING="$ROOT/packaging/macos"

echo "🍎 Sowing macOS DMG 빌드 — v${VERSION}"
echo "─────────────────────────────────────"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

# ─── 1. Info.plist (버전 치환) ───
echo "📝 Info.plist 생성"
sed "s/__VERSION__/${VERSION}/g" "$PACKAGING/Info.plist" > "$APP/Contents/Info.plist"

# ─── 2. 런처 스크립트 ───
echo "🚀 launcher.sh → MacOS/Sowing"
cp "$PACKAGING/launcher.sh" "$APP/Contents/MacOS/Sowing"
chmod +x "$APP/Contents/MacOS/Sowing"

# ─── 3. 소스 복사 (.app 안에 번들) ───
echo "📦 소스 복사 → Resources/sowing/"
SOURCE_DIR="$APP/Contents/Resources/sowing"
mkdir -p "$SOURCE_DIR"
# rsync 로 제외 목록 적용
rsync -a \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='tmp/' \
  --exclude='log/' \
  --exclude='dist/' \
  --exclude='.claude' \
  --exclude='.bundle' \
  --exclude='vendor/bundle' \
  --exclude='node_modules' \
  --exclude='packaging/macos/build.sh' \
  --exclude='spec/' \
  --exclude='examples.txt' \
  --exclude='.rspec_status' \
  "$ROOT/" "$SOURCE_DIR/"

# ─── 4. 아이콘 (없으면 placeholder) ───
ICON_SRC="$PACKAGING/Sowing.icns"
if [ -f "$ICON_SRC" ]; then
  echo "🎨 아이콘 복사"
  cp "$ICON_SRC" "$APP/Contents/Resources/Sowing.icns"
else
  echo "⚠  Sowing.icns 없음 — placeholder 빈 파일 생성 (배포 전 실 아이콘 권장)"
  : > "$APP/Contents/Resources/Sowing.icns"
fi

# ─── 5. (선택) 코드 사이닝 ───
if [ -n "${SOWING_CODESIGN_IDENTITY:-}" ]; then
  echo "🔏 codesign — identity: ${SOWING_CODESIGN_IDENTITY}"
  codesign --force --deep --sign "$SOWING_CODESIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  echo "✅ codesign 완료"
else
  echo "⚠  코드 사이닝 건너뜀 (SOWING_CODESIGN_IDENTITY 미설정)"
  echo "   사용자는 Gatekeeper 우회 필요 — DMG README.txt 안내 동봉"
fi

# ─── 6. DMG 스테이징 폴더 ───
echo "💿 DMG 스테이징 조립"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/$APP_NAME"
ln -s /Applications "$DMG_STAGE/Applications"

# README.txt — Gatekeeper 우회 안내
cat > "$DMG_STAGE/먼저 읽어주세요.txt" <<EOF
Sowing 🌱 v${VERSION} — macOS 설치

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Sowing.app 을 Applications 폴더로 드래그하세요.

2. Applications 폴더에서 Sowing 을 더블클릭.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠ Gatekeeper 경고 시 (코드 사이닝 미적용 빌드):

  "Sowing.app 은 검증되지 않은 개발자가 만들었기 때문에..." 메시지가 뜨면:

  방법 1: 우클릭 → "열기" → "열기"
    (이후로는 일반 더블클릭 작동)

  방법 2: 터미널에서:
    xattr -dr com.apple.quarantine /Applications/Sowing.app

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ 첫 실행:
  - Terminal 창이 열리면서 자동 설치 (1~2분)
  - 완료 시 브라우저가 자동으로 http://127.0.0.1:48723 열림

✅ 종료:
  - Terminal 창을 닫거나 ⌃C 누르면 Sowing 종료

✅ Vault 위치:
  ~/Documents/SowingVault (default)
  변경: 환경 변수 SOWING_VAULT 설정

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📚 자세한 사용법: https://github.com/junkicho-lab/sowing
🐛 문제 신고:    https://github.com/junkicho-lab/sowing/issues

EOF

# ─── 7. DMG 생성 ───
echo "💿 DMG 압축 (UDZO)"
rm -f "$DMG_OUT"
hdiutil create \
  -volname "Sowing ${VERSION}" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_OUT"

# ─── 8. SHA256 ───
echo "🔐 SHA256 체크섬"
shasum -a 256 "$DMG_OUT" > "${DMG_OUT}.sha256"
cat "${DMG_OUT}.sha256"

# ─── 9. (선택) notarize ───
if [ -n "${SOWING_NOTARIZE_PROFILE:-}" ]; then
  echo "📨 notarize submit — profile: ${SOWING_NOTARIZE_PROFILE}"
  xcrun notarytool submit "$DMG_OUT" \
    --keychain-profile "$SOWING_NOTARIZE_PROFILE" \
    --wait
  echo "📌 staple 진행"
  xcrun stapler staple "$DMG_OUT"
  echo "✅ notarize 완료"
else
  echo "⚠  notarize 건너뜀 (SOWING_NOTARIZE_PROFILE 미설정)"
fi

# ─── 10. 결과 ───
echo ""
echo "─────────────────────────────────────"
echo "✅ DMG 빌드 완료"
echo ""
echo "산출물:"
ls -lh "$DMG_OUT" "${DMG_OUT}.sha256"
echo ""
echo "검증:"
echo "  open '$DMG_OUT'                                # DMG 마운트"
echo "  spctl -a -v '$APP'                             # Gatekeeper 평가 (codesign 필요)"
echo "  stapler validate '$DMG_OUT'                    # notarize staple 검증"
