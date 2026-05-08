#!/usr/bin/env bash
# Sowing 단일 바이너리 빌드 드라이버 (W8-T02).
#
# Tebako 도커 이미지를 사용해 OS별 바이너리를 빌드한다.
# 사용:
#   ./packaging/build.sh           # 현재 OS만
#   ./packaging/build.sh linux     # 특정 OS만
#   ./packaging/build.sh all       # 지원 OS 모두
#
# 사전 요구사항:
#   - Docker (linux 빌드)
#   - macOS native (macOS 빌드, 호스트에서 직접)
#   - Windows: 별도 VM 또는 GitHub Actions
#
# 산출물:
#   dist/sowing-${VERSION}-${OS}-${ARCH}  (Linux/macOS)
#   dist/sowing-${VERSION}-${OS}-${ARCH}.exe  (Windows)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(ruby -r ./lib/sowing/version -e 'print Sowing::VERSION')"
TARGET="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
DIST="$ROOT/dist"
mkdir -p "$DIST"

echo "🔨 Sowing v${VERSION} 빌드 시작 — 대상: ${TARGET}"

build_linux() {
  local arch="${1:-x86_64}"
  local out="$DIST/sowing-${VERSION}-linux-${arch}"
  echo "🐧 Linux ${arch} 빌드..."
  docker run --rm \
    -v "$ROOT:/mnt/workspace" \
    --platform "linux/${arch}" \
    ghcr.io/tamatebako/tebako:latest \
    press \
      --root=/mnt/workspace \
      --entry-point=bin/sowing \
      --output="/mnt/workspace/dist/sowing-${VERSION}-linux-${arch}" \
      --Ruby=4.0.3
  echo "✅ ${out}"
}

build_macos() {
  local arch="${1:-arm64}"
  local out="$DIST/sowing-${VERSION}-macos-${arch}"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "⚠  macOS 빌드는 macOS 호스트에서만 가능 — skip"
    return 0
  fi
  echo "🍎 macOS ${arch} 빌드..."
  # Tebako native (Docker 미사용) — macOS에서 직접 실행
  tebako press \
    --root="$ROOT" \
    --entry-point=bin/sowing \
    --output="$out" \
    --Ruby=4.0.3
  echo "✅ ${out}"
  echo "ℹ  codesign + notarize는 packaging/macos/build.sh 참조 (W8-T03)"
}

build_windows() {
  echo "🪟 Windows 빌드는 GitHub Actions 또는 Windows VM에서 진행"
  echo "   → packaging/windows/build.ps1 참조 (W8-T04)"
}

case "$TARGET" in
  linux)   build_linux ;;
  macos|darwin) build_macos ;;
  windows) build_windows ;;
  all)
    build_linux x86_64
    build_linux aarch64
    build_macos arm64
    build_macos x86_64
    build_windows
    ;;
  *)
    echo "❌ 알 수 없는 타겟: ${TARGET}"
    echo "사용: $0 [linux|macos|windows|all]"
    exit 1
    ;;
esac

echo ""
echo "📦 산출물:"
ls -lh "$DIST" 2>/dev/null || echo "   (없음 — 빌드 실패?)"
