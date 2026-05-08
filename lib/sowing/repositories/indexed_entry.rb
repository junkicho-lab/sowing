# frozen_string_literal: true

module Sowing
  module Repositories
    # 인덱스 조회 결과 (메타데이터 전용).
    # 본문(body)은 마크다운 파일에만 있으므로 본 클래스에 포함되지 않는다.
    # 풀 도메인 객체가 필요하면 caller가 vault_repo.read(path)로 별도 조회한다.
    #
    # mode: Symbol (:memo/:note/:record)
    # tags: Array<String> (TagSet 정책으로 정규화된 정렬된 태그)
    # created_at, updated_at, indexed_at: Time
    # file_mtime: Integer (Unix epoch seconds)
    IndexedEntry = Data.define(
      :id, :path, :mode, :title, :category, :template, :source, :promoted_from,
      :created_at, :updated_at, :file_mtime, :file_hash, :word_count, :indexed_at,
      :tags
    )
  end
end
