# frozen_string_literal: true

require "front_matter_parser"

RSpec.describe "샘플 콘텐츠 (W7-T02)" do
  let(:samples_dir) { File.expand_path("../templates/samples", __dir__) }
  let(:sample_files) { Dir.glob(File.join(samples_dir, "*.md")).sort }

  it "정확히 12개 — 메모 4 + 필기 4 + 기록 4 (ROADMAP W7-T02)" do
    expect(sample_files.size).to eq(12)
    by_mode = sample_files.group_by { |f| File.basename(f).split("-").first }
    expect(by_mode["memo"].size).to eq(4)
    expect(by_mode["note"].size).to eq(4)
    expect(by_mode["record"].size).to eq(4)
  end

  describe "각 샘플 파일" do
    it "frontmatter에 is_sample: true 표시 (ADR-005 시드 식별용)" do
      sample_files.each do |path|
        parsed = FrontMatterParser::Parser.new(:md).call(File.read(path))
        expect(parsed.front_matter["is_sample"]).to be(true), "#{File.basename(path)}: is_sample 누락"
      end
    end

    it "VaultRepo가 도메인으로 복원 가능 (id/created_at/mode 등 필수 필드 충족)" do
      vault_repo = Sowing::Repositories::VaultRepo.new(vault_dir: Dir.mktmpdir("samples-spec-"))
      sample_files.each do |path|
        # VaultRepo.read는 파일 경로를 받아 frontmatter 파싱 + 도메인 복원
        FileUtils.cp(path, File.join(vault_repo.vault_dir, File.basename(path)))
        entry = vault_repo.read(File.basename(path))
        expect(entry).to be_a(Sowing::Domain::Memo).or be_a(Sowing::Domain::Note).or be_a(Sowing::Domain::Record)
        expect(entry.id).to be_a(Sowing::Domain::ValueObjects::Ulid)
        expect(entry.created_at).to be_a(Time)
      end
      FileUtils.rm_rf(vault_repo.vault_dir)
    end

    it "ULID는 모두 고유 (시드 시 충돌 없음)" do
      ids = sample_files.map do |path|
        FrontMatterParser::Parser.new(:md).call(File.read(path)).front_matter["id"]
      end
      expect(ids.uniq.size).to eq(12)
    end
  end

  describe "위키링크 그래프 시연 가능 (ROADMAP)" do
    let(:contents) { sample_files.map { |f| File.read(f) } }

    it "최소 3개의 [[위키링크]]가 분포해야 함 (그래프 노드·엣지 시연)" do
      total_links = contents.sum { |c| c.scan(/\[\[[^\]]+\]\]/).size }
      expect(total_links).to be >= 3
    end

    it "위키링크 타겟이 되는 record title이 실제 존재 (broken link 없도록)" do
      record_titles = sample_files.grep(/record/).map do |path|
        FrontMatterParser::Parser.new(:md).call(File.read(path)).front_matter["title"]
      end

      # 본문에 등장하는 [[X]] 중 record title을 노리는 것은 매칭되어야 함.
      referenced = contents.flat_map { |c| c.scan(/\[\[([^\]]+)\]\]/).flatten }.uniq
      expect(referenced).to include("수업 회고: 협동학습 첫주")
      expect(referenced).to include("학생 관찰: 민준")
      expect(record_titles).to include("수업 회고: 협동학습 첫주")
      expect(record_titles).to include("학생 관찰: 민준")
    end
  end

  describe "옵시디언 호환성" do
    it "note/record는 H1 제목으로 시작 (memo는 title 없는 짧은 텍스트라 예외)" do
      sample_files.each do |path|
        next if File.basename(path).start_with?("memo-")
        parsed = FrontMatterParser::Parser.new(:md).call(File.read(path))
        body = parsed.content.strip
        expect(body).to match(/\A#\s+\S/), "#{File.basename(path)}: 본문이 H1으로 시작하지 않음"
      end
    end

    it "한글 태그(#xxx) 본문에 포함 — 한국 교사 검색 패턴" do
      sample_files.each do |path|
        body = FrontMatterParser::Parser.new(:md).call(File.read(path)).content
        expect(body).to match(/#[가-힣]+/), "#{File.basename(path)}: 한글 태그 없음"
      end
    end
  end
end
