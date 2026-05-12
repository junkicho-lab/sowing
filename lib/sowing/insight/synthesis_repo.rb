# frozen_string_literal: true

require "fileutils"

module Sowing
  module Insight
    # Insight::SynthesisRepo — 합성 결과 파일 영속화 (Phase R Stage 4a R4a-T02).
    #
    # 책임:
    #   - .sowing/synth/{type}/{slug}.md 파일 읽기·쓰기·목록·삭제
    #   - Synthesis 객체 ↔ 마크다운 파일 변환
    #   - DB 인덱싱 없음 — synth artifact 는 file-only (entries 테이블 비참여)
    #
    # 옛 SynthController 의 list_synth / parse_synth_file 헬퍼를 도메인 계층으로 끌어올림.
    # SynthController 는 Strangler Fig 로 점진 위임 가능 (R4a-T04 후보).
    #
    # 의존: Core (Filesystem, Markdown::Parser).
    class SynthesisRepo
      SYNTH_DIR = ".sowing/synth"

      def initialize(vault_dir: nil, parser: nil)
        @vault_dir = Pathname.new((vault_dir || Core::Paths.vault_dir).to_s).expand_path
        @parser = parser || Core::Markdown::Parser.new
      end

      # Synthesis 객체를 파일로 영속화 (atomic write).
      # 같은 slug 가 있으면 덮어쓰기 (재합성 시 synth_at 갱신, 멱등).
      # @param synth [Sowing::Insight::Synthesis]
      # @param slug [String] 파일명 (확장자 제외). 미지정 시 target slug 사용.
      # @return [Pathname] 저장된 절대 경로
      def write(synth, slug: nil)
        unless synth.is_a?(Synthesis)
          raise ArgumentError, "synth 는 Sowing::Insight::Synthesis 이어야 합니다 (받은 타입: #{synth.class})"
        end

        slug ||= default_slug(synth)
        target = type_dir(synth.type).join("#{slug}.md")
        FileUtils.mkdir_p(target.dirname)
        File.write(target, synth.to_markdown, encoding: "UTF-8")
        target
      end

      # 단건 조회 — type + slug 로 파일 읽기.
      # @return [Sowing::Insight::Synthesis, nil]
      def find(type:, slug:)
        path = type_dir(type).join("#{slug}.md")
        return nil unless path.exist?
        read_synth(path, type)
      end

      # 대기 중인 모든 synthesis 결과.
      # @param type [Symbol, String, nil] 특정 type 만 필터 (nil = 전체)
      # @return [Array<Sowing::Insight::Synthesis>]
      def pending(type: nil)
        types = type ? [type.to_sym] : SYNTHESIZER_TYPES.map(&:to_sym)
        types.flat_map do |t|
          dir = type_dir(t)
          next [] unless dir.exist?
          Dir.glob(dir.join("*.md")).sort.filter_map { |p| read_synth(Pathname.new(p), t) }
        end
      end

      # @return [Integer] 대기 중 synthesis 파일 수.
      def count_pending(type: nil)
        pending(type: type).size
      end

      # 거절 — 휴지통 이동 (영구 삭제 0, CLAUDE.md 원칙 5).
      # @return [Pathname, nil] 휴지통 위치 (파일 없으면 nil)
      def reject(type:, slug:)
        path = type_dir(type).join("#{slug}.md")
        return nil unless path.exist?

        rel = path.relative_path_from(@vault_dir)
        trash = @vault_dir.join(".sowing/trash", rel)
        FileUtils.mkdir_p(trash.dirname)
        target = avoid_collision(trash)
        FileUtils.mv(path.to_s, target.to_s)
        target
      end

      private

      def type_dir(type)
        @vault_dir.join(SYNTH_DIR, type.to_s)
      end

      # 파일명 슬러그 — Synthesis.target ("student:김철수") 의 ":" 뒤 부분.
      # self-mirror:daily-2026-05-12 → daily-2026-05-12
      def default_slug(synth)
        synth.target.split(":", 2).last.to_s
      end

      def read_synth(path, type)
        parsed = @parser.parse(path.read(encoding: "UTF-8"))
        fm = parsed.frontmatter
        return nil unless fm["is_synth"] == true

        # 표준 키 추출
        standard_keys = %w[is_synth synth_target synth_at synth_source_count synth_model title]
        extras = fm.reject { |k, _| standard_keys.include?(k) }

        Synthesis.new(
          type: type.to_sym,
          target: fm.fetch("synth_target"),
          title: fm.fetch("title", path.basename(".md").to_s),
          body: parsed.body.to_s.sub(/\A# .+\n+/, "").chomp, # H1 제거 (frontmatter title 과 중복)
          synth_at: Time.iso8601(fm.fetch("synth_at")),
          source_count: fm["synth_source_count"].to_i,
          model: fm["synth_model"],
          extras: extras,
          path: path.relative_path_from(@vault_dir)
        )
      rescue => e
        Sowing.logger&.warn("Synthesis 파일 파싱 실패 (#{path}): #{e.message}")
        nil
      end

      def avoid_collision(path)
        return path unless path.exist?
        base = path.basename(".md").to_s
        dir = path.dirname
        (2..999).each do |n|
          candidate = dir.join("#{base}-#{n}.md")
          return candidate unless candidate.exist?
        end
        raise "휴지통 충돌 회피 실패: #{path}"
      end
    end
  end
end
