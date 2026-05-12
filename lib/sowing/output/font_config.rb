# frozen_string_literal: true

module Sowing
  module Output
    # Output::FontConfig — 한글 폰트 경로 resolver (Phase R R4b-followup).
    #
    # PDF 출력 시 한글 (CJK) 문자 렌더링을 위해 TTF 폰트 등록 필수. Prawn 의
    # 기본 PDF 폰트 (Helvetica) 는 ASCII 만 지원 — 한글이 나오면 \uXXXX 가 깨짐.
    #
    # 조회 우선순위:
    #   1. ENV["SOWING_PDF_FONT"] (사용자 명시 경로)
    #   2. vendor/fonts/Pretendard-Regular.ttf (선택적 vendoring — 기본 미포함)
    #   3. /System/Library/Fonts/Supplemental/AppleGothic.ttf (macOS 기본)
    #   4. /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc (Linux 일반)
    #   5. 못 찾으면 FontNotFound 예외 + 설치 가이드 안내
    #
    # 권장 폰트:
    #   - Pretendard (SIL Open Font License) — https://github.com/orioncactus/pretendard
    #     설치 후 ENV["SOWING_PDF_FONT"]=/path/to/Pretendard-Regular.ttf
    #
    # 의존: Core 만.
    class FontConfig
      class FontNotFound < StandardError; end

      # vendor/fonts/ — Pretendard Regular/Bold OTF 가 함께 vendoring 됨 (R4b-followup).
      VENDORED_REGULAR = File.expand_path("../../../vendor/fonts/Pretendard-Regular.ttf", __dir__)
      VENDORED_BOLD = File.expand_path("../../../vendor/fonts/Pretendard-Bold.ttf", __dir__)

      MACOS_FALLBACKS = [
        "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
        "/System/Library/Fonts/AppleSDGothicNeo.ttc" # TTC — Prawn 호환 제한적
      ].freeze

      LINUX_FALLBACKS = [
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
        "/usr/share/fonts/opentype/source-han-sans/SourceHanSansK-Regular.otf"
      ].freeze

      class << self
        # @return [String] 사용 가능한 TTF/OTF 폰트의 절대 경로
        # @raise [FontNotFound] 어디에도 폰트 없을 때 (메시지에 설치 가이드)
        def resolve
          candidates = build_candidates
          found = candidates.find { |p| p && File.file?(p) && supported_format?(p) }
          return found if found

          raise FontNotFound, build_install_instructions(candidates)
        end

        # 폰트 존재 여부만 확인 (raise 없음).
        # @return [Boolean]
        def available?
          resolve
          true
        rescue FontNotFound
          false
        end

        # Bold variant 별도 경로 — vendored Bold 가 있으면 반환, 아니면 nil.
        # PDF 헤딩 굵게 표시 시 활용 (없으면 Prawn 이 normal 합성).
        # @return [String, nil]
        def bold_path
          return ENV["SOWING_PDF_FONT_BOLD"] if ENV["SOWING_PDF_FONT_BOLD"] && !ENV["SOWING_PDF_FONT_BOLD"].empty?
          return VENDORED_BOLD if File.file?(VENDORED_BOLD)
          nil
        end

        private

        def build_candidates
          list = []
          list << ENV["SOWING_PDF_FONT"] if ENV["SOWING_PDF_FONT"] && !ENV["SOWING_PDF_FONT"].empty?
          list << VENDORED_REGULAR

          case host_os
          when :macos then list.concat(MACOS_FALLBACKS)
          when :linux then list.concat(LINUX_FALLBACKS)
          end
          list
        end

        def host_os
          case RbConfig::CONFIG["host_os"]
          when /darwin/ then :macos
          when /linux/ then :linux
          when /mingw|mswin/ then :windows
          else :unknown
          end
        end

        # Prawn 은 .ttf 와 .otf 만 안정 지원. .ttc 는 폰트 collection 으로 첫 face 만
        # subset 추출 가능하나 호환성 이슈 있음 — 일단 .ttf/.otf 우선.
        def supported_format?(path)
          %w[.ttf .otf].include?(File.extname(path).downcase)
        end

        def build_install_instructions(checked)
          <<~MSG
            한글 PDF 출력을 위한 TTF 폰트를 찾지 못했습니다.

            확인한 경로:
            #{checked.compact.map { |p| "  - #{p}" }.join("\n")}

            해결 방법 (택일):

            1) Pretendard 폰트 설치 (권장):
               https://github.com/orioncactus/pretendard/releases 에서
               Pretendard-Regular.ttf 다운로드 후:

               export SOWING_PDF_FONT=/path/to/Pretendard-Regular.ttf

               또는 vendor/fonts/ 에 복사:
               cp Pretendard-Regular.ttf vendor/fonts/

            2) 시스템 한글 폰트 사용:
               - macOS: AppleGothic 이 기본 설치되어 있어야 합니다.
               - Linux: sudo apt install fonts-nanum 또는 fonts-noto-cjk

            3) ENV 변수로 임의 TTF 지정:
               export SOWING_PDF_FONT=/path/to/your-korean.ttf
          MSG
        end
      end
    end
  end
end
