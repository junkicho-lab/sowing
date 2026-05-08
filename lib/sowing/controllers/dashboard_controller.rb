# frozen_string_literal: true

module Sowing
  module Controllers
    # 대시보드(홈). 사용자가 진입하는 첫 화면.
    # SPEC §10.3 와이어프레임 참조.
    class DashboardController < ApplicationController
      RECENT_LIMIT = 5

      helpers do
        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        end

        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        # 최근 메모 N건. 인덱스로 빠르게 정렬·페이징, body는 마크다운 파일에서 로드.
        # 파일이 누락된 인덱스 row는 건너뜀 (정합성 깨진 경우 graceful).
        def recent_memos(limit: RECENT_LIMIT)
          index_repo.list(mode: :memo).first(limit).filter_map do |indexed|
            vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            nil
          end
        end
      end

      get "/" do
        @page_title = "대시보드"
        @recent_memos = recent_memos
        erb :"dashboard/show", layout: :"layouts/application"
      end
    end
  end
end
