# frozen_string_literal: true

module Sowing
  module Repositories
    # 인덱스 조회 결과 (메타데이터 전용).
    # 본문(body)은 마크다운 파일에만 있으므로 본 클래스에 포함되지 않는다.
    # 풀 도메인 객체가 필요하면 caller가 vault_repo.read(path)로 별도 조회한다.
    #
    # mode: Symbol (:memo/:note/:record/:plan)
    # subject: Symbol or nil (:person/:subject/:document/:identity, ADR-016 — R2-T05)
    # archived_at: Time or nil (ADR-017 — R3-T05)
    # archive_reason: String or nil (보관 사유 자유 텍스트)
    # tags: Array<String> (TagSet 정책으로 정규화된 정렬된 태그)
    # created_at, updated_at, indexed_at: Time
    # file_mtime: Integer (Unix epoch seconds)
    IndexedEntry = Data.define(
      :id, :path, :mode, :title, :category, :template, :source, :promoted_from,
      :created_at, :updated_at, :file_mtime, :file_hash, :word_count, :indexed_at,
      :tags, :subject, :archived_at, :archive_reason
    ) do
      # 보관 여부 — Façade·뷰 분기에 활용.
      def archived?
        !archived_at.nil?
      end
    end
  end
end
