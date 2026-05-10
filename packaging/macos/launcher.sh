#!/bin/bash
# Sowing.app 런처 — 더블클릭 시 실행됨.
#
# 동작:
#   1. macOS 시스템 Ruby (3.3+) 또는 Homebrew Ruby 자동 탐지
#   2. 첫 실행: Terminal 에서 setup wizard (bundle install + db:setup)
#   3. 매번: Terminal 에서 dev 서버 + 브라우저 자동 열림
#
# 사용자가 Terminal 창을 닫으면 Sowing 종료 — 프로세스 lifecycle 명확.

set -e

APP_BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
SOWING_DIR="$APP_BUNDLE/Resources/sowing"
SUPPORT_DIR="$HOME/Library/Application Support/Sowing"
mkdir -p "$SUPPORT_DIR"

# ─── Ruby 탐지 — macOS 14.4+ 시스템 Ruby (3.3.x) 또는 Homebrew ───
RUBY_BIN=""
for candidate in \
    /opt/homebrew/opt/ruby/bin/ruby \
    /usr/local/opt/ruby/bin/ruby \
    "$(command -v ruby 2>/dev/null || true)" \
    /usr/bin/ruby; do
  if [ -x "$candidate" ]; then
    if "$candidate" -e 'exit RUBY_VERSION >= "3.3.0" ? 0 : 1' 2>/dev/null; then
      RUBY_BIN="$candidate"
      break
    fi
  fi
done

if [ -z "$RUBY_BIN" ]; then
  osascript <<APPLESCRIPT
display dialog "Sowing 은 Ruby 3.3+ 가 필요합니다.

설치 옵션:
  1. Homebrew: brew install ruby
  2. mise (권장): curl https://mise.run | sh && mise use --global ruby@3.3
  3. asdf / rbenv

설치 후 Sowing 을 다시 실행해 주세요." buttons {"설치 가이드 열기", "취소"} default button 1 with title "Sowing — Ruby 필요"
APPLESCRIPT
  if [ "$?" = "0" ]; then
    open "https://github.com/junkicho-lab/sowing/blob/main/SETUP.md"
  fi
  exit 1
fi

export PATH="$(dirname "$RUBY_BIN"):$PATH"

# ─── Bundler 확인 ───
if ! command -v bundle >/dev/null 2>&1; then
  "$RUBY_BIN" -S gem install bundler --no-document 2>/dev/null || true
fi

# ─── Terminal 에서 Sowing 실행 ───
# osascript 로 Terminal 새 창 + 명령 실행. 사용자가 Terminal 닫으면 종료.
INSTALLED_FLAG="$SUPPORT_DIR/.installed"

if [ ! -f "$INSTALLED_FLAG" ]; then
  # 첫 실행 — setup
  CMD="cd '$SOWING_DIR' && \
echo '🌱 Sowing 첫 실행 — 설치 중 (1~2분)...' && \
bundle config set --local without 'development test' && \
bundle install --jobs 4 --retry 3 && \
bundle exec rake db:setup && \
touch '$INSTALLED_FLAG' && \
echo '' && \
echo '✅ 설치 완료. 잠시 후 브라우저가 열립니다.' && \
echo '' && \
(sleep 3 && open 'http://127.0.0.1:48723') & \
exec bundle exec rackup -p 48723 -o 127.0.0.1"
else
  # 재실행 — 서버만
  CMD="cd '$SOWING_DIR' && \
echo '🌱 Sowing 시작' && \
echo '브라우저: http://127.0.0.1:48723' && \
echo '종료: 이 Terminal 창을 닫거나 ⌃C' && \
echo '' && \
(sleep 2 && open 'http://127.0.0.1:48723') & \
exec bundle exec rackup -p 48723 -o 127.0.0.1"
fi

# osascript 안에서 quote escape 주의 — 단일 인용 안의 작은따옴표 처리
osascript <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "$CMD"
end tell
APPLESCRIPT
