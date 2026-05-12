# frozen_string_literal: true

module Sowing
  module Output
    # Output::TemplateRegistry — 5 default ERB template loader (Phase R Stage 4b R4b-T02).
    #
    # 조회 우선순위 (ADR-018, 게이트 #4 a):
    #   1. 사용자 override: {vault}/.sowing/templates/exports/{type}.md.erb
    #   2. 시스템 default: {source_root}/templates/exports/{type}.md.erb
    #
    # 학교·연도별 양식 차이는 사용자가 override ERB 파일을 vault 에 작성하여 흡수.
    # 시스템 default 는 변경 안 함 — 업데이트가 사용자 커스터마이즈를 깨지 않음.
    #
    # 의존: Core::Paths.
    class TemplateRegistry
      SYSTEM_DIR = File.expand_path("../../../templates/exports", __dir__)
      USER_SUBPATH = ".sowing/templates/exports"

      def initialize(vault_dir: nil, system_dir: SYSTEM_DIR)
        @user_dir = if vault_dir
          Pathname.new(vault_dir.to_s).join(USER_SUBPATH)
        else
          begin
            Pathname.new(Core::Paths.vault_dir.to_s).join(USER_SUBPATH)
          rescue
            nil # 부트 전·테스트 환경에서 vault 없을 때 user override 비활성
          end
        end
        @system_dir = Pathname.new(system_dir.to_s)
      end

      # @param type [Symbol] TEMPLATE_TYPES 중 하나
      # @param format [Symbol] FORMATS — Stage 4b 는 :markdown 만 (확장 시 .pdf.erb / .docx.erb 패턴)
      # @return [Sowing::Output::Template]
      # @raise [ArgumentError] 시스템·사용자 모두 ERB 파일 없을 때
      def find(type:, format: :markdown)
        ext = extension_for(format)
        filename = "#{type}#{ext}"

        path = locate(filename)
        raise ArgumentError, "Template 못 찾음: type=#{type.inspect} format=#{format.inspect} " \
          "(검색 위치: #{@user_dir}, #{@system_dir})" unless path

        Template.new(
          type: type,
          format: format,
          source_path: path,
          erb_source: path.read(encoding: "UTF-8")
        )
      end

      # @return [Array<Symbol>] 시스템 default 로 제공되는 type 목록 (5 종).
      def system_types
        Pathname.glob(File.join(@system_dir, "*.md.erb")).map do |path|
          path.basename.to_s.sub(/\.md\.erb\z/, "").to_sym
        end.sort
      end

      private

      def locate(filename)
        candidates = []
        candidates << @user_dir.join(filename) if @user_dir
        candidates << @system_dir.join(filename)
        candidates.find { |p| p.file? }
      end

      def extension_for(format)
        # markdown → .md.erb (Stage 4b MVP).
        # 향후 :pdf → .pdf.erb (Prawn DSL) / :docx → .docx.erb (caracal DSL).
        case format.to_sym
        when :markdown then ".md.erb"
        when :pdf then ".pdf.erb"
        when :docx then ".docx.erb"
        else raise ArgumentError, "지원하지 않는 format: #{format.inspect}"
        end
      end
    end
  end
end
