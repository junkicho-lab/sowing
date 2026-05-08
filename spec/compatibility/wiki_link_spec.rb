# frozen_string_literal: true

# 옵시디언 호환성 — 위키링크.
#
# CLAUDE.md 원칙 2: 옵시디언이 인식 가능한 형식만 사용한다.
# 본 spec은 "옵시디언이 본 마크다운으로 받았을 때" 와 "본 앱이 그 마크다운에서 추출했을 때"
# 의미가 일치함을 검증한다.

require "fileutils"
require "tmpdir"

RSpec.describe "옵시디언 위키링크 호환성", type: :compatibility do
  let(:wiki_link) { Sowing::Infrastructure::Markdown::WikiLink }

  describe "옵시디언 표준 형식 인식" do
    it "[[Note Title]] — 가장 단순한 형식" do
      links = wiki_link.extract("참조: [[Note Title]]")
      expect(links.size).to eq(1)
      expect(links.first.target).to eq("Note Title")
    end

    it "[[Note Title|Alias]] — 별칭 표기" do
      links = wiki_link.extract("[[2026-05-08|오늘]]")
      expect(links.first.target).to eq("2026-05-08")
      expect(links.first.display).to eq("오늘")
    end

    it "[[Folder/Note]] — 경로 포함 (옵시디언 폴더 표기)" do
      links = wiki_link.extract("[[20_Notes/lessons/1단원]]")
      expect(links.first.target).to eq("20_Notes/lessons/1단원")
    end

    it "한국어 target — 옵시디언 한국어 사용자 일반 패턴" do
      links = wiki_link.extract("[[5월 학급운영 회고]] [[연구노트|메모]]")
      expect(links.map(&:target)).to eq(["5월 학급운영 회고", "연구노트"])
      expect(links.map(&:display)).to eq(["5월 학급운영 회고", "메모"])
    end
  end

  describe "여러 위치에서의 등장" do
    it "헤더 안의 위키링크" do
      md = "# [[제목 노트]] 내용\n"
      expect(wiki_link.extract(md).first.target).to eq("제목 노트")
    end

    it "리스트 항목의 위키링크" do
      md = "- 항목 [[A]]\n- 항목 [[B|별칭]]\n"
      expect(wiki_link.extract(md).map(&:target)).to eq(%w[A B])
    end

    it "blockquote 안의 위키링크" do
      md = "> 인용 [[참고]]\n"
      expect(wiki_link.extract(md).first.target).to eq("참고")
    end

    it "테이블 셀 안의 위키링크" do
      md = "| 항목 | 링크 |\n|------|------|\n| 1 | [[관련]] |\n"
      expect(wiki_link.extract(md).first.target).to eq("관련")
    end
  end

  describe "round-trip 보존 (옵시디언 ↔ 본 앱)" do
    it "마크다운에 들어간 [[…]] 텍스트가 변하지 않는다 (extract → to_markdown 일치)" do
      original_links = ["[[A]]", "[[B|별칭]]", "[[20_Notes/lessons/1단원]]"]
      original_links.each do |raw|
        links = wiki_link.extract(raw)
        expect(links.size).to eq(1)
        expect(links.first.to_markdown).to eq(raw)
      end
    end

    it "VaultRepo write/read를 거쳐도 [[…]] 텍스트가 보존된다" do
      tmpdir = Pathname.new(Dir.mktmpdir("compat-wiki-"))
      begin
        repo = Sowing::Repositories::VaultRepo.new(vault_dir: tmpdir)
        memo = Sowing::Domain::Memo.new(
          id: Sowing::Domain::ValueObjects::Ulid.generate,
          body: "오늘 [[5월 회고]] 와 [[수업|복습]]을 정리했다.",
          created_at: Time.new(2026, 5, 8, 9, 0, 0, "+09:00")
        )
        path = repo.write(memo)
        restored = repo.read(path)

        # 본문 텍스트 raw 보존
        expect(restored.body).to include("[[5월 회고]]")
        expect(restored.body).to include("[[수업|복습]]")

        # 추출 결과 동일
        expect(wiki_link.extract(restored.body).map(&:to_markdown))
          .to eq(["[[5월 회고]]", "[[수업|복습]]"])
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  describe "옵시디언이 인식하지 않는 형식과 동일하게 무시" do
    it "공백만의 target [[ ]] 은 위키링크 아님" do
      expect(wiki_link.extract("[[   ]]")).to be_empty
    end

    it "단일 [...] 는 일반 마크다운 링크 (옵시디언도 동일)" do
      expect(wiki_link.extract("[link](url)")).to be_empty
    end

    it "닫히지 않은 [[ 는 위키링크 아님" do
      expect(wiki_link.extract("[[never closed")).to be_empty
    end
  end

  describe "변환 결과의 옵시디언 호환성" do
    it "transform 결과는 마크다운 파일에 쓰지 않는다 (HTML은 표시용)" do
      # 디자인 의도 검증: SafeWriter는 도메인의 to_markdown 결과만 받음.
      # transform 결과(HTML <a>)는 view 렌더링 시점에만 사용 — markdown 파일에는 [[…]] 그대로.
      memo = Sowing::Domain::Memo.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        body: "[[참고]] 본문",
        created_at: Time.now
      )
      expect(memo.to_markdown).to include("[[참고]]")
      expect(memo.to_markdown).not_to include("<a")
    end
  end
end
