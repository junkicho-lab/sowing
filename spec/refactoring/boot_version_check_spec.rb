# frozen_string_literal: true

# Phase 16 follow-up — Boot-time schema version check (no-such-column 회귀 방지).
RSpec.describe "Boot-time schema version check" do
  let(:db) { Sowing::Core::DB.connection }

  describe "Sowing::EXPECTED_DB_VERSION 상수" do
    it "Sowing 모듈 직속 상수로 노출" do
      expect(Sowing).to be_const_defined(:EXPECTED_DB_VERSION)
    end

    it "Integer 이고 10 이상 (Phase R 마이그레이션 010 까지 포함)" do
      expect(Sowing::EXPECTED_DB_VERSION).to be_a(Integer)
      expect(Sowing::EXPECTED_DB_VERSION).to be >= 10
    end

    it "현재 schema_info 가 기대 버전 이상 (테스트 환경에서 마이그레이션 모두 적용됨)" do
      current = db[:schema_info].get(:version).to_i
      expect(current).to be >= Sowing::EXPECTED_DB_VERSION
    end
  end

  describe ".verify_db_version!" do
    it "테스트 환경에서는 스킵 (spec_helper.rb 가 매번 migrate)" do
      # SOWING_ENV=test 이미 설정되어 있음 → verify_db_version! 호출 시 즉시 return
      expect { Sowing.verify_db_version! }.not_to output.to_stderr
    end

    it "production 환경에서 버전 미달이면 STDERR 경고" do
      original_env = Sowing.env
      Sowing.env = "development"
      begin
        # schema_info 의 version 을 임시로 낮춤 → 다시 원복
        db.transaction(rollback: :always) do
          db[:schema_info].update(version: 0)
          expect { Sowing.verify_db_version! }.to output(/마이그레이션 누락/).to_stderr
        end
      ensure
        Sowing.env = original_env
      end
    end

    it "DB 오류 시에도 raise 없이 진단만" do
      original_env = Sowing.env
      Sowing.env = "development"
      begin
        # schema_info 가 사라진 상황 흉내 — verify_db_version! 가 tables.include? 로 가드
        allow(db).to receive(:tables).and_return([:entries]) # schema_info 미포함
        expect { Sowing.verify_db_version! }.not_to raise_error
      ensure
        Sowing.env = original_env
      end
    end
  end
end
