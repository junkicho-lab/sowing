# frozen_string_literal: true

require "caracal"
require "commonmarker"
require "tempfile"

module Sowing
  module Output
    # Output::DocxRenderer — markdown String → DOCX bytes (Phase R R4b-followup).
    #
    # commonmarker AST 를 walk 하여 caracal Word 명령을 발행. caracal 은 한글 글리프 를
    # 별도 폰트 등록 없이 처리 — Word·LibreOffice 가 시스템 폰트로 자동 fallback.
    #
    # 지원 마크다운 features:
    #   - H1 / H2 / H3 → h1 / h2 / h3 caracal helpers
    #   - paragraph (inline strong / emph 처리)
    #   - list / item (unordered bullet)
    #   - table / table_row / table_cell (caracal table)
    #   - thematic_break (page-width 가로선, hr)
    #
    # caracal 은 save-to-file 모델 — File.write 후 binread 으로 bytes 반환.
    #
    # 의존: caracal (외부 gem), commonmarker.
    class DocxRenderer
      H_MAP = {1 => :h1, 2 => :h2, 3 => :h3, 4 => :h4, 5 => :h5, 6 => :h6}.freeze

      # @param markdown [String]
      # @return [String] DOCX binary (ASCII-8BIT 인코딩 — File.binwrite 사용 필수)
      def render(markdown)
        Tempfile.create(["sowing-docx-", ".docx"]) do |tmp|
          doc = Caracal::Document.new(tmp.path)
          walk_block(doc, Commonmarker.parse(ensure_utf8(markdown)))
          doc.save
          File.binread(tmp.path)
        end
      end

      private

      def walk_block(doc, node)
        node.each do |child|
          case child.type
          when :document
            walk_block(doc, child)
          when :heading
            render_heading(doc, child)
          when :paragraph
            render_paragraph(doc, child)
          when :list
            render_list(doc, child)
          when :table
            render_table(doc, child)
          when :thematic_break
            doc.hr
          when :code_block
            render_code_block(doc, child)
          when :block_quote
            walk_block(doc, child) # caracal 의 quote 스타일 미사용 — 단순 위임
          else
            render_paragraph(doc, child) if child.respond_to?(:each)
          end
        end
      end

      def render_heading(doc, node)
        level = node.header_level
        method = H_MAP[level] || :h6
        text = inline_text(node)
        doc.public_send(method, text)
      end

      def render_paragraph(doc, node)
        runs = inline_runs(node)
        return if runs.empty?

        # caracal 의 p 블록은 ParagraphModel context 에서 instance_eval — outer
        # 변수만 캡쳐 가능, 메서드 호출 불가. runs 를 미리 normalize.
        prepared = runs.map { |r|
          {
            text: r[:text],
            bold: r[:styles].include?(:bold),
            italic: r[:styles].include?(:italic)
          }
        }

        doc.p do
          prepared.each do |r|
            args = {}
            args[:bold] = true if r[:bold]
            args[:italics] = true if r[:italic]
            text(r[:text], **args)
          end
        end
      end

      def render_list(doc, list_node)
        # caracal 의 ul 블록은 ListModel context 에서 instance_eval 됨 — outer self
        # 의 helper 메서드 접근 불가. 미리 아이템 텍스트를 수집한 뒤 블록에 넘김.
        items = []
        list_node.each do |item|
          next unless item.type == :item
          text = collect_item_text(item)
          items << text unless text.empty?
        end

        doc.ul do
          items.each { |t| li t }
        end
      end

      def render_table(doc, table_node)
        rows = []
        table_node.each do |row_node|
          next unless row_node.type == :table_row
          cells = []
          row_node.each do |cell_node|
            cells << inline_text(cell_node) if cell_node.type == :table_cell
          end
          rows << cells
        end
        return if rows.empty?

        doc.table(rows, border_size: 4) do
          cell_style cells, font: "Pretendard", size: 20
        end
      rescue
        # Caracal 의 table DSL 이 환경에 따라 변동 — 단순 paragraph fallback.
        rows.each do |row|
          doc.p row.join(" | ")
        end
      end

      def render_code_block(doc, node)
        text = (node.respond_to?(:string_content) ? node.string_content.to_s : "")
        return if text.empty?
        doc.p text, font: "Courier New", size: 18
      end

      # ── Inline ─────────────────────────────────────────────

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
          when :code, :link
            runs.concat(inline_runs(child, base_styles: base_styles)) if child.respond_to?(:each)
          else
            runs.concat(inline_runs(child, base_styles: base_styles)) if child.respond_to?(:each)
          end
        end
        runs
      end

      def inline_text(node)
        inline_runs(node).map { |r| r[:text] }.join
      end

      def collect_item_text(item_node)
        # list item 안의 paragraph 들의 텍스트 평탄화 (중첩 list 미지원 — 단순 처리)
        parts = []
        item_node.each do |child|
          parts << inline_text(child) if child.type == :paragraph
        end
        parts.join(" ").strip
      end

      def text_of(node)
        return "" unless node.respond_to?(:string_content)
        node.string_content.to_s
      rescue TypeError
        ""
      end

      def ensure_utf8(str)
        return str if str.encoding == Encoding::UTF_8
        str.dup.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
