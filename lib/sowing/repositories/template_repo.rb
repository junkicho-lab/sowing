# frozen_string_literal: true

require "fileutils"
require "pathname"

module Sowing
  module Repositories
    # 템플릿 저장소 (W6-T04). vault/templates/*.md를 SoT로 사용.
    #
    # 저장 형식: 순수 마크다운 (frontmatter 없음). 파일명(.md 제외)이 곧 slug + 표시명.
    # 옵시디언으로 직접 편집해도 호환되며, vault 동기화·백업 정책의 혜택을 받는다.
    #
    # 치환 엔진은 단순 {{key}} gsub — Liquid/ERB 의존성 없이 충분.
    # default_context는 date/time/year/datetime/date_korean 등 자주 쓰이는 변수.
    class TemplateRepo
      Template = Data.define(:slug, :name, :content, :path)

      SLUG_RE = /\A[A-Za-z0-9가-힣_-]+\z/
      MAX_SLUG_LENGTH = 80
      PLACEHOLDER_RE = /\{\{\s*(\w+)\s*\}\}/

      def initialize(vault_dir:,
        clock: Time,
        safe_writer: Infrastructure::Filesystem::SafeWriter.new)
        @templates_dir = Pathname.new(vault_dir.to_s).expand_path.join("templates")
        @clock = clock
        @safe_writer = safe_writer
      end

      attr_reader :templates_dir

      # @return [Array<Template>] slug 정렬
      def list
        return [] unless @templates_dir.exist?
        Dir.glob(@templates_dir.join("*.md")).sort.map { |p| build_from_path(Pathname.new(p)) }
      end

      # @param slug [String]
      # @return [Template, nil]
      def find(slug)
        return nil unless valid_slug?(slug)
        path = @templates_dir.join("#{slug}.md")
        return nil unless path.exist?
        build_from_path(path)
      end

      # 신규/덮어쓰기. SafeWriter로 원자적 기록.
      # @return [Template]
      def save(slug:, content:)
        raise ArgumentError, "유효하지 않은 slug — 한글/영문/숫자/하이픈/언더스코어, 최대 #{MAX_SLUG_LENGTH}자" unless valid_slug?(slug)
        FileUtils.mkdir_p(@templates_dir)
        target = @templates_dir.join("#{slug}.md")
        @safe_writer.atomic_write(target, content.to_s)
        build_from_path(target)
      end

      # @param content [String]   템플릿 본문 ({{key}} 포함 가능)
      # @param context [Hash]     사용자 제공 변수. default_context와 merge.
      # @return [String] 치환 결과. 알 수 없는 key는 원문 유지(정보 보존).
      def render(content, context = {})
        full = default_context.merge(context.transform_keys(&:to_sym))
        content.to_s.gsub(PLACEHOLDER_RE) do |match|
          key = Regexp.last_match(1).to_sym
          full.key?(key) ? full[key].to_s : match
        end
      end

      private

      def build_from_path(path)
        slug = path.basename(".md").to_s
        Template.new(slug: slug, name: slug, content: path.read, path: path)
      end

      def valid_slug?(slug)
        slug.is_a?(String) && slug.length <= MAX_SLUG_LENGTH && slug.match?(SLUG_RE)
      end

      def default_context
        now = @clock.now
        weekday = %w[일 월 화 수 목 금 토][now.wday]
        {
          date: now.strftime("%Y-%m-%d"),
          time: now.strftime("%H:%M"),
          datetime: now.iso8601,
          year: now.year.to_s,
          month: now.month.to_s.rjust(2, "0"),
          day: now.day.to_s.rjust(2, "0"),
          date_korean: "#{now.year}년 #{now.month}월 #{now.day}일 #{weekday}요일"
        }
      end
    end
  end
end
