# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Sowing::MCP::Server do
  describe "#new" do
    it "공식 ::MCP::Server 인스턴스를 래핑" do
      server = described_class.new
      expect(server.server).to be_a(::MCP::Server)
      expect(server.server.name).to eq("sowing")
      expect(server.server.version).to eq(Sowing::VERSION)
    end

    it "4개 sensor 도구 등록 (list_memos / search / read_entry / health)" do
      tool_names = described_class::TOOLS.map(&:tool_name)
      expect(tool_names).to contain_exactly("list_memos", "search", "read_entry", "health")
    end

    it "instructions 에 Sowing 도메인 모델 안내 포함" do
      server = described_class.new
      expect(server.server.instance_variable_get(:@instructions)).to include("메모", "필기", "기록")
    end
  end
end

RSpec.describe Sowing::MCP do
  describe ".repositories (DI 싱글턴)" do
    after { described_class.reset! }

    it "기본 — Paths.vault_dir 기반 VaultRepo + IndexRepo" do
      repos = described_class.repositories
      expect(repos[:vault]).to be_a(Sowing::Repositories::VaultRepo)
      expect(repos[:index]).to be_a(Sowing::Repositories::IndexRepo)
    end

    it "테스트 격리 — repositories= 로 override" do
      custom = {vault: :stub_vault, index: :stub_index}
      described_class.repositories = custom
      expect(described_class.repositories).to equal(custom)
    end

    it "reset! 으로 default 복귀" do
      described_class.repositories = {vault: :stub, index: :stub}
      described_class.reset!
      expect(described_class.repositories[:vault]).to be_a(Sowing::Repositories::VaultRepo)
    end
  end
end
