# Homebrew formula for Sowing 🌱
#
# 설치 (Tap 등록 후):
#   brew tap junkicho-lab/sowing
#   brew install sowing
#
# 또는 직접:
#   brew install junkicho-lab/sowing/sowing
#
# 운영자 메모:
#   - Tap 저장소 (`homebrew-sowing`) 별도 생성 후 본 파일 복사
#   - sha256 는 GitHub Release 의 source tarball 으로 갱신
#   - Apple Developer 계정 불필요 (formula 는 source 다운로드 + 빌드)

class Sowing < Formula
  desc "한국 교사용 로컬 우선 노트 도구 — 마크다운 SoT, 옵시디언 호환, LLM 합성 12종"
  homepage "https://github.com/junkicho-lab/sowing"
  url "https://github.com/junkicho-lab/sowing/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256_AFTER_RELEASE"
  license "MIT"
  head "https://github.com/junkicho-lab/sowing.git", branch: "main"

  depends_on "ruby" => "~> 3.3"
  depends_on "sqlite"

  uses_from_macos "libyaml"

  def install
    # bundle install (production 의존성만)
    ENV["BUNDLE_DEPLOYMENT"] = "true"
    ENV["BUNDLE_WITHOUT"] = "development:test"
    system "bundle", "install", "--jobs", "4", "--retry", "3"

    # 앱 디렉토리 + bin shim 설치
    libexec.install Dir["*"]
    (bin/"sowing").write_env_script libexec/"bin/sowing", BUNDLE_GEMFILE: libexec/"Gemfile"
    (bin/"sowing-doctor").write_env_script libexec/"bin/sowing-doctor", BUNDLE_GEMFILE: libexec/"Gemfile"
    (bin/"sowing-mcp").write_env_script libexec/"bin/sowing-mcp", BUNDLE_GEMFILE: libexec/"Gemfile"

    # 첫 실행 안내
    ohai "✅ Sowing 설치 완료"
    ohai "다음 단계:"
    ohai "  sowing dev          # 개발 서버 (http://127.0.0.1:48723)"
    ohai "  sowing-doctor       # 시스템 진단"
    ohai "  sowing memo \"...\"   # CLI 메모"
    ohai ""
    ohai "Vault 위치 (default): ~/Documents/SowingVault"
    ohai "  변경: export SOWING_VAULT=/your/path"
  end

  test do
    # 정상 부팅 + doctor 0-issue 검증
    output = shell_output("#{bin}/sowing-doctor 2>&1", 0)
    assert_match "Sowing Doctor", output
    assert_match "환경", output
  end
end
