# frozen_string_literal: true

module Sowing
  module Core
    # `.env` 파일을 ENV 로 로딩하는 가벼운 자체 파서 (외부 gem 0).
    #
    # 사용:
    #   Sowing::Core::Dotenv.load(Sowing.root)
    #
    # 우선순위 (뒤가 앞을 덮지 않음):
    #   1. 시스템 ENV (이미 export 된 값) — 절대 덮지 않음
    #   2. .env.local (개인 비밀, gitignore 됨)
    #   3. .env       (프로젝트 공통 기본값)
    #
    # 형식 (bash 호환 부분집합):
    #   KEY=value
    #   KEY="value with spaces and # not-a-comment"
    #   KEY='single quoted'
    #   export KEY=value      # bash 의 export 접두어 허용
    #   # 주석 라인
    #   KEY=                  # 빈 값
    #
    # 비지원 (단순함 우선):
    #   - 변수 보간 (${VAR}, $VAR)
    #   - 다중라인 값
    #   - 명령 치환 ($(cmd), `cmd`)
    #
    # 키에 비밀이 들어갈 수 있으므로 파싱 실패 시에도 값은 절대 로깅하지 않음.
    module Dotenv
      # 우선순위 순서 (뒤가 시스템 ENV 보다 약함, 앞이 강함)
      FILES = [".env.local", ".env"].freeze

      module_function

      # @param root [String, Pathname] 프로젝트 루트
      # @return [Array<String>] 실제 로딩한 파일 경로 (없으면 [])
      def load(root)
        loaded = []
        FILES.each do |name|
          path = File.join(root.to_s, name)
          next unless File.file?(path)
          parse_into_env(path)
          loaded << path
        end
        loaded
      end

      # 파일 한 개를 파싱해 ENV 에 머지. 시스템 ENV 가 우선.
      def parse_into_env(path)
        File.foreach(path, encoding: "UTF-8") do |raw|
          line = raw.strip
          next if line.empty? || line.start_with?("#")

          # 'export ' 접두어 허용
          line = line.sub(/\Aexport\s+/, "")

          key, _eq, rest = line.partition("=")
          key = key.strip
          next if key.empty? || !key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)

          # 시스템 ENV 가 이미 있으면 절대 덮지 않음 — 운영자가 명시 export 한 값 우선
          next if ENV.key?(key)

          ENV[key] = unquote_and_strip_inline_comment(rest)
        end
      end

      # 따옴표 처리 + 따옴표 밖 인라인 주석 제거.
      # "..." / '...' 안의 # 은 주석이 아님.
      def unquote_and_strip_inline_comment(value)
        v = value.strip
        return "" if v.empty?

        if v.start_with?('"') && (close = v.index('"', 1))
          v[1...close]
        elsif v.start_with?("'") && (close = v.index("'", 1))
          v[1...close]
        else
          # 따옴표 없음 — 첫 # 부터는 주석 (단, 공백으로 둘러싸인 # 만)
          stripped = v.sub(/\s+#.*\z/, "")
          stripped.strip
        end
      end
    end
  end
end
