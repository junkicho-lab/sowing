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

# ─── Ruby 탐지 ───
# .app 더블클릭 시 GUI 컨텍스트라 shell rc 가 로드되지 않음 — mise/rbenv/asdf
# 의 PATH 가 비어있으므로 shim 경로를 명시적으로 검사.
#
# 검사 우선순위 (먼저 발견 + 3.3+ 만족하면 사용):
#   1. mise (`mise which ruby`) — 권장 도구
#   2. rbenv shims
#   3. asdf shims
#   4. Homebrew (시스템·인텔)
#   5. PATH 의 ruby (login shell 환경에서만 의미)
#   6. macOS 시스템 Ruby (14.4+ 가 3.3.x)
RUBY_BIN=""

# 시스템 PATH 에 자주 사용되는 도구 위치 추가 (mise/rbenv/asdf 가 PATH 검색에 의존하는 경우)
export PATH="$HOME/.local/bin:$HOME/.rbenv/bin:$HOME/.asdf/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# 1. mise — `mise which ruby` 가 정확한 경로를 반환
if command -v mise >/dev/null 2>&1; then
  candidate="$(mise which ruby 2>/dev/null || true)"
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    if "$candidate" -e 'exit RUBY_VERSION >= "3.3.0" ? 0 : 1' 2>/dev/null; then
      RUBY_BIN="$candidate"
    fi
  fi
fi

# 2~6. 위에서 못 찾으면 명시적 경로 목록 검사
if [ -z "$RUBY_BIN" ]; then
  for candidate in \
      "$HOME/.local/share/mise/shims/ruby" \
      "$HOME/.rbenv/shims/ruby" \
      "$HOME/.asdf/shims/ruby" \
      /opt/homebrew/opt/ruby/bin/ruby \
      /usr/local/opt/ruby/bin/ruby \
      "$(command -v ruby 2>/dev/null || true)" \
      /usr/bin/ruby; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      if "$candidate" -e 'exit RUBY_VERSION >= "3.3.0" ? 0 : 1' 2>/dev/null; then
        RUBY_BIN="$candidate"
        break
      fi
    fi
  done
fi

if [ -z "$RUBY_BIN" ]; then
  # 진단 정보 — 사용자가 어떤 경로를 검사했는지 확인 가능
  DIAG=""
  for p in mise "$HOME/.local/share/mise/shims/ruby" "$HOME/.rbenv/shims/ruby" \
           "$HOME/.asdf/shims/ruby" /opt/homebrew/opt/ruby/bin/ruby \
           /usr/local/opt/ruby/bin/ruby /usr/bin/ruby; do
    if [ "$p" = "mise" ]; then
      command -v mise >/dev/null 2>&1 && DIAG="$DIAG✓ mise (which ruby 결과 없음)\n" || DIAG="$DIAG✗ mise\n"
    elif [ -e "$p" ]; then
      v="$("$p" -e 'print RUBY_VERSION' 2>/dev/null || echo "?")"
      DIAG="$DIAG✓ $p (Ruby $v)\n"
    else
      DIAG="$DIAG✗ $p\n"
    fi
  done

  osascript <<APPLESCRIPT
display dialog "Sowing 은 Ruby 3.3+ 가 필요합니다.

검사된 경로:
$(printf "$DIAG")
설치 옵션:
  1. Homebrew: brew install ruby
  2. mise (권장): curl https://mise.run | sh && mise use --global ruby@3.3
  3. asdf / rbenv

이미 mise/rbenv 로 설치돼 있다면 — Sowing.app 은 GUI 컨텍스트라 shell rc 가
로드되지 않아 PATH 가 비어있을 수 있습니다. Terminal 에서 \\\"bin/sowing dev\\\"
직접 실행을 권장합니다." buttons {"설치 가이드 열기", "취소"} default button 1 with title "Sowing — Ruby 필요"
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
