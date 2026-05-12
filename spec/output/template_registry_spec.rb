# frozen_string_literal: true

require "tmpdir"

# Phase R Stage 4b R4b-T02 — Output::TemplateRegistry (5 default ERB loader).
RSpec.describe Sowing::Output::TemplateRegistry do
  describe "시스템 default 5 종" do
    subject(:registry) { described_class.new }

    it "system_types — 5 종 모두 발견 (게이트 #3 c)" do
      expect(registry.system_types).to contain_exactly(
        :student_record, :consultation, :meeting_minutes,
        :project_proposal, :budget_request
      )
    end

    Sowing::Output::TEMPLATE_TYPES.each do |type|
      it "find(type: #{type.inspect}, format: :markdown) → Template 반환" do
        t = registry.find(type: type)
        expect(t).to be_a(Sowing::Output::Template)
        expect(t.type).to eq(type)
        expect(t.format).to eq(:markdown)
        expect(t.erb_source).not_to be_empty
      end
    end

    it "format: :pdf — 시스템 default 미존재 → ArgumentError" do
      expect { registry.find(type: :student_record, format: :pdf) }
        .to raise_error(ArgumentError, /못 찾음/)
    end
  end

  describe "사용자 override 우선" do
    let(:user_vault) { Pathname.new(Dir.mktmpdir("user-vault-")) }

    before do
      override_dir = user_vault.join(".sowing/templates/exports")
      FileUtils.mkdir_p(override_dir)
      File.write(override_dir.join("student_record.md.erb"), "USER OVERRIDE: <%= student_name %>")
    end

    after { FileUtils.rm_rf(user_vault) }

    it "사용자 ERB 가 있으면 system default 보다 우선" do
      registry = described_class.new(vault_dir: user_vault)
      template = registry.find(type: :student_record)
      expect(template.render(student_name: "김철수")).to eq("USER OVERRIDE: 김철수")
    end

    it "사용자 override 가 없는 type 은 system default 사용" do
      registry = described_class.new(vault_dir: user_vault)
      template = registry.find(type: :consultation)
      expect(template.erb_source).to include("상담 기록")
    end
  end
end
