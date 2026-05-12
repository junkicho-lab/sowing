# frozen_string_literal: true

module Sowing
  module Controllers
    # 메모 작성·표시. POST /memos는 빠른 메모 모달의 제출을 받아 처리.
    # Turbo Stream으로 응답하여 페이지 리로드 없이 대시보드 갱신.
    class MemosController < ApplicationController
      TURBO_STREAM_TYPE = "text/vnd.turbo-stream.html"
      PER_PAGE = 30
      MAX_PAGE = 10_000

      NOTE_CATEGORIES = UseCases::CreateNote::CATEGORIES

      ERROR_MESSAGES = {
        empty_title: "제목을 입력해 주세요.",
        empty_category: "카테고리를 입력해 주세요.",
        invalid_category: "유효하지 않은 카테고리입니다.",
        empty_source: "출처를 입력해 주세요.",
        not_found: "메모를 찾을 수 없습니다.",
        not_a_memo: "이 항목은 메모가 아닙니다.",
        not_promotable: "이 항목은 승격 대상이 아닙니다.",
        file_missing: "메모 파일이 존재하지 않습니다."
      }.freeze

      helpers do
        # 메모 생성 helper 제거됨 (R2-T04 Strangler Fig) — POST /memos 가
        # Sowing::Capture.create_item 직접 호출. UseCases::CreateMemo 는
        # MCP::Tools::CreateMemo 만 사용 (별도 strangulation 후보).

        def promote_to_note_use_case
          UseCases::PromoteToNote.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def promote_to_record_use_case
          UseCases::PromoteToRecord.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Core::Paths.vault_dir)
        end

        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        # 페이지의 메모 도메인 객체. 인덱스로 페이징, body는 파일에서.
        def load_memo_page(page:, per_page:)
          offset = (page - 1) * per_page
          index_repo.list(mode: :memo, limit: per_page, offset: offset).filter_map do |indexed|
            vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            nil
          end
        end

        def find_memo(id)
          indexed = index_repo.find(id)
          return nil if indexed.nil? || indexed.mode != :memo
          vault_repo.read(indexed.path)
        rescue Errno::ENOENT
          nil
        end

        def note_categories
          NotesController::CATEGORIES
        end

        def parse_tags(raw)
          raw.to_s.split(/[\s,]+/).reject(&:empty?)
        end

        def memo_error_message(failure)
          ERROR_MESSAGES.fetch(failure, "처리 실패: #{failure}")
        end

        def halt_with_404(message)
          status 404
          @page_title = "찾을 수 없음"
          @message = message
          halt erb(:"errors/404", layout: :"layouts/application")
        end
      end

      get "/memos" do
        @page_title = "메모"
        @page = (params["page"] || 1).to_i.clamp(1, MAX_PAGE)
        @per_page = PER_PAGE
        @total = index_repo.count(mode: :memo)
        @total_pages = [(@total / @per_page.to_f).ceil, 1].max
        @memos = load_memo_page(page: @page, per_page: @per_page)
        erb :"memos/index", layout: :"layouts/application"
      end

      # Phase R Stage 2 R2-T04 — Strangler Fig.
      # UseCases::CreateMemo → Sowing::Capture.create_item Façade 로 위임.
      # Item 은 Memo 와 duck-type 호환 (id/body/created_at) — 템플릿 무수정.
      # CreateMemo Use Case 자체는 MCP::Tools::CreateMemo 가 아직 사용 (별도 strangulation).
      #
      # Phase 16 P16-T02 — subject 4축 (ADR-016) 옵셔널 수신.
      # quick_modal 의 chip (native radio button) 이 subject 파라미터 전송.
      #
      # 2026-05-12 — chip 선택 시 body 끝에 "분류: {라벨} #{라벨}" 자동 부착.
      #   예) subject=person → "...\n\n분류: 인물 #인물"
      #   분류명 (plain) + 태그 (#) 둘 다 — 검색·시각 인지·태그 인덱싱 모두 지원.
      #   멱등 — 이미 본문에 같은 패턴 있으면 중복 부착 회피.
      post "/memos" do
        raw_body = params["body"].to_s
        subject_param = params["subject"].to_s
        subject = subject_param.empty? ? nil : subject_param.to_sym

        body = if subject && Sowing::Capture::Item::SUBJECT_LABELS.key?(subject)
          label = Sowing::Capture::Item::SUBJECT_LABELS[subject]
          line = "분류: #{label} ##{label}"
          raw_body.include?(line) ? raw_body : "#{raw_body.rstrip}\n\n#{line}"
        else
          raw_body
        end

        begin
          item = Sowing::Capture.create_item(body: body, subject: subject)
          content_type TURBO_STREAM_TYPE
          erb :"memos/created.turbo_stream", layout: false, locals: {memo: item}
        rescue ArgumentError => e
          status 422
          content_type TURBO_STREAM_TYPE
          failure = e.message.include?("subject") ? :invalid_subject : :empty_body
          erb :"memos/error.turbo_stream", layout: false, locals: {failure: failure}
        end
      end

      get "/memos/:id/promote_to_note" do
        @memo = find_memo(params["id"])
        halt_with_404(ERROR_MESSAGES[:not_found]) if @memo.nil?

        @page_title = "필기로 승격"
        @form = {
          title: nil,
          category: nil,
          source: nil,
          tags: @memo.tags.to_a.join(", ")
        }
        @error = nil
        erb :"memos/promote_to_note", layout: :"layouts/application"
      end

      post "/memos/:id/promote_to_note" do
        result = promote_to_note_use_case.call(
          id: params["id"],
          title: params["title"].to_s,
          category: params["category"].to_s,
          source: params["source"].to_s,
          tags: parse_tags(params["tags"])
        )

        if result.success?
          redirect "/notes/#{result.value!.id}"
        elsif [:not_found, :not_a_memo, :file_missing].include?(result.failure)
          halt_with_404(memo_error_message(result.failure))
        else
          @memo = find_memo(params["id"]) || halt_with_404(ERROR_MESSAGES[:not_found])
          @page_title = "필기로 승격"
          @form = {
            title: params["title"],
            category: params["category"],
            source: params["source"],
            tags: params["tags"]
          }
          @error = memo_error_message(result.failure)
          status 422
          erb :"memos/promote_to_note", layout: :"layouts/application"
        end
      end

      get "/memos/:id/promote_to_record" do
        @memo = find_memo(params["id"])
        halt_with_404(ERROR_MESSAGES[:not_found]) if @memo.nil?

        # 2026-05-12 — 메모의 subject (4축 ENUM) 을 IndexRepo 에서 읽어와
        # promote 폼의 카테고리 prefill 에 활용. Domain::Memo 는 subject 미보유 →
        # 별도 변수로 노출.
        indexed = index_repo.find(params["id"])
        @memo_subject = indexed&.subject # :person / :subject / :document / :identity / nil

        @page_title = "기록으로 승격"
        @form = {
          title: nil,
          category: nil,
          tags: @memo.tags.to_a.join(", ")
        }
        @categories = index_repo.distinct_categories(mode: :record)
        @error = nil
        erb :"memos/promote_to_record", layout: :"layouts/application"
      end

      post "/memos/:id/promote_to_record" do
        result = promote_to_record_use_case.call(
          id: params["id"],
          title: params["title"].to_s,
          category: params["category"].to_s,
          tags: parse_tags(params["tags"])
        )

        if result.success?
          redirect "/records/#{result.value!.id}"
        elsif [:not_found, :not_promotable, :file_missing].include?(result.failure)
          halt_with_404(memo_error_message(result.failure))
        else
          @memo = find_memo(params["id"]) || halt_with_404(ERROR_MESSAGES[:not_found])
          @page_title = "기록으로 승격"
          @form = {
            title: params["title"],
            category: params["category"],
            tags: params["tags"]
          }
          @categories = index_repo.distinct_categories(mode: :record)
          @error = memo_error_message(result.failure)
          status 422
          erb :"memos/promote_to_record", layout: :"layouts/application"
        end
      end
    end
  end
end
