# frozen_string_literal: true

require "prawn"
require "prawn/table"
require "commonmarker"

module Sowing
  module Output
    # Output::PdfRenderer — markdown String → PDF bytes (Phase R R4b-followup).
    #
    # 한글 텍스트 지원을 위해 시스템·사용자 TTF 폰트를 등록하고 default font 로 사용.
    # commonmarker AST 를 walk 하여 Prawn 명령을 발행 — 다음 마크다운 features 지원:
    #   - H1 / H2 / H3 (header_level → font_size 매핑)
    #   - paragraph (formatted_text 로 inline 강조 처리)
    #   - strong / emph (bold / italic)
    #   - list / item (unordered, 들여쓰기 bullet)
    #   - table / table_row / table_cell (prawn-table)
    #   - thematic_break (가로 구분선)
    #
    # 미지원 (Stage 4b-followup 범위 밖): 코드 블록·이미지·링크·각주.
    # 5 default ERB templates 가 사용하는 features 만 커버.
    #
    # 의존: Prawn (`prawn` + `prawn-table` 외부 gem), Output::FontConfig.
    class PdfRenderer
      H_SIZES = {1 => 22, 2 => 16, 3 => 13}.freeze
      DEFAULT_FONT_SIZE = 11
      LINE_HEIGHT_GAP = 5

      # @param font_path [String, nil] 사용자 명시 폰트 (nil 이면 FontConfig.resolve)
      def initialize(font_path: nil)
        @font_path = font_path
      end

      # @param markdown [String] 렌더할 마크다운 본문
      # @return [String] PDF binary (UTF-8 인코딩 X — File.write 시 binmode 사용)
      def render(markdown)
        font_path = @font_path || FontConfig.resolve

        pdf = Prawn::Document.new(
          page_size: "A4",
          margin: [50, 50, 60, 50]
        )

        register_font(pdf, font_path)
        pdf.font("Korean")
        pdf.font_size DEFAULT_FONT_SIZE

        doc = Commonmarker.parse(ensure_utf8(markdown))
        walk_block(pdf, doc)

        pdf.render
      end

      private

      def register_font(pdf, font_path)
        bold_path = FontConfig.bold_path || font_path
        pdf.font_families.update(
          "Korean" => {
            normal: font_path,
            bold: bold_path,
            italic: font_path, # 한글 italic 미지원 — 시각 효과 약함, fallback OK
            bold_italic: bold_path
          }
        )
      end

      # 블록 노드 (heading, paragraph, list, table, document) walk.
      def walk_block(pdf, node)
        node.each do |child|
          case child.type
          when :document
            walk_block(pdf, child)
          when :heading
            render_heading(pdf, child)
          when :paragraph
            render_paragraph(pdf, child)
          when :list
            render_list(pdf, child)
          when :table
            render_table(pdf, child)
          when :thematic_break
            render_thematic_break(pdf)
          when :code_block
            render_code_block(pdf, child)
          when :block_quote
            render_block_quote(pdf, child)
          else
            # 알 수 없는 block 은 plain text 로 폴백
            render_paragraph(pdf, child) if child.respond_to?(:each)
          end
        end
      end

      def render_heading(pdf, node)
        level = node.header_level
        size = H_SIZES[level] || DEFAULT_FONT_SIZE
        runs = inline_runs(node)
        pdf.move_down LINE_HEIGHT_GAP
        pdf.formatted_text(runs.map { |r| r.merge(size: size, styles: ((r[:styles] || []) + [:bold]).uniq) })
        pdf.move_down LINE_HEIGHT_GAP / 2.0
      end

      def render_paragraph(pdf, node)
        runs = inline_runs(node)
        return if runs.empty?
        pdf.formatted_text(runs)
        pdf.move_down LINE_HEIGHT_GAP
      end

      def render_list(pdf, list_node)
        list_node.each do |item|
          next unless item.type == :item
          item.each do |child|
            case child.type
            when :paragraph
              runs = inline_runs(child)
              next if runs.empty?
              # "• " bullet 을 첫 번째 run 에 prepend
              first = runs.first.dup
              first[:text] = "• #{first[:text]}"
              runs[0] = first
              pdf.formatted_text(runs, indent_paragraphs: 10)
            when :list
              # 중첩 list — 들여쓰기 추가
              pdf.indent(15) { render_list(pdf, child) }
            end
          end
        end
        pdf.move_down LINE_HEIGHT_GAP
      end

      def render_table(pdf, table_node)
        rows = []
        table_node.each do |row_node|
          next unless row_node.type == :table_row
          cells = []
          row_node.each do |cell_node|
            cells << cell_text(cell_node) if cell_node.type == :table_cell
          end
          rows << cells
        end

        return if rows.empty?

        pdf.move_down LINE_HEIGHT_GAP
        pdf.table(rows,
          header: true,
          row_colors: ["F0F0F0", "FFFFFF"],
          cell_style: {font: "Korean", size: DEFAULT_FONT_SIZE - 1, padding: [4, 5]})
        pdf.move_down LINE_HEIGHT_GAP
      end

      def render_thematic_break(pdf)
        pdf.move_down LINE_HEIGHT_GAP
        pdf.stroke_horizontal_rule
        pdf.move_down LINE_HEIGHT_GAP
      end

      def render_code_block(pdf, node)
        text = (node.respond_to?(:string_content) ? node.string_content.to_s : "")
        return if text.empty?
        pdf.fill_color "F5F5F5"
        pdf.fill_rectangle [0, pdf.cursor], pdf.bounds.width, 20 + text.lines.size * 14
        pdf.fill_color "000000"
        pdf.formatted_text([{text: text, styles: [], size: DEFAULT_FONT_SIZE - 1}])
        pdf.move_down LINE_HEIGHT_GAP
      end

      def render_block_quote(pdf, node)
        pdf.indent(20) { walk_block(pdf, node) }
      end

      # ── inline 처리 ────────────────────────────────────────────

      # paragraph / heading / list_item 내부의 inline 노드들을 formatted_text run 으로 변환.
      # @return [Array<Hash>] [{text: "...", styles: [:bold]}, ...]
      def inline_runs(node, base_styles: [])
        runs = []
        node.each do |child|
          case child.type
          when :text
            runs << {text: text_of(child), styles: base_styles.dup}
          when :strong
            runs.concat(inline_runs(child, base_styles: base_styles + [:bold]))
          when :emph
            runs.concat(inline_runs(child, base_styles: base_styles + [:italic]))
          when :softbreak
            runs << {text: " ", styles: base_styles.dup}
          when :linebreak
            runs << {text: "\n", styles: base_styles.dup}
          when :code
            runs << {text: text_of(child), styles: base_styles.dup, font: "Courier"}
          when :link
            # 링크 표시 텍스트만 (URL 은 footnote 화 가능 — 현재 단순 처리)
            runs.concat(inline_runs(child, base_styles: base_styles))
          else
            # 알 수 없는 inline 은 자식 walk
            runs.concat(inline_runs(child, base_styles: base_styles)) if child.respond_to?(:each)
          end
        end
        runs
      end

      def text_of(node)
        return "" unless node.respond_to?(:string_content)
        node.string_content.to_s
      rescue TypeError
        ""
      end

      # table cell 의 inline 을 단일 String 으로 평탄화 (prawn-table 은 run 미지원).
      def cell_text(cell_node)
        inline_runs(cell_node).map { |r| r[:text] }.join
      end

      def ensure_utf8(str)
        return str if str.encoding == Encoding::UTF_8
        str.dup.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
