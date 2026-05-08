# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::Repositories::VaultRepo do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("vault-spec-")) }
  let(:repo) { described_class.new(vault_dir: vault_dir) }
  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:created_at) { Time.new(2026, 5, 8, 9, 23, 14, "+09:00") }

  after do
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  def build_memo(**overrides)
    Sowing::Domain::Memo.new(
      id: ulid, body: "오늘 1교시", created_at: created_at, **overrides
    )
  end

  def build_note(**overrides)
    Sowing::Domain::Note.new(
      id: ulid, body: "필기", created_at: created_at, category: "lessons", **overrides
    )
  end

  def build_record(**overrides)
    Sowing::Domain::Record.new(
      id: ulid, body: "기록", created_at: created_at, category: "학급운영", **overrides
    )
  end

  describe "#write" do
    context "Memo" do
      it "00_Inbox/YYYY-MM-DD_HHmmss.md 경로에 저장한다" do
        path = repo.write(build_memo)
        expect(path).to eq(vault_dir.join("00_Inbox/2026-05-08_092314.md"))
        expect(path).to exist
      end

      it "쓰여진 내용은 Parser로 round-trip 가능하다" do
        path = repo.write(build_memo)
        memo2 = repo.read(path)
        expect(memo2.id).to eq(ulid)
        expect(memo2.mode).to eq(:memo)
        expect(memo2.body).to eq("오늘 1교시")
      end
    end

    context "Note" do
      it "20_Notes/{category}/{title}.md 경로에 저장한다 (title 있을 때)" do
        path = repo.write(build_note(title: "1단원 정리"))
        expect(path).to eq(vault_dir.join("20_Notes/lessons/1단원 정리.md"))
      end

      it "title이 nil이면 timestamp를 파일명으로 쓴다" do
        path = repo.write(build_note(title: nil))
        expect(path).to eq(vault_dir.join("20_Notes/lessons/2026-05-08_092314.md"))
      end

      it "category가 없으면 ArgumentError" do
        expect { repo.write(build_note(category: nil)) }
          .to raise_error(ArgumentError, /category/)
      end
    end

    context "Record" do
      it "30_Records/{YYYY}/{category}/{title}.md 경로에 저장한다" do
        path = repo.write(build_record(title: "5월 회고"))
        expect(path).to eq(vault_dir.join("30_Records/2026/학급운영/5월 회고.md"))
      end

      it "category가 없으면 ArgumentError" do
        expect { repo.write(build_record(category: nil)) }
          .to raise_error(ArgumentError, /category/)
      end
    end

    context "title 슬러그 처리" do
      it "크로스플랫폼 비호환 문자(\\/<>:\"|?*)는 -로 치환된다" do
        path = repo.write(build_note(title: '수업 후기: 1/2단원 "정리"?'))
        expect(path.basename.to_s).to eq("수업 후기- 1-2단원 -정리--.md")
      end

      it "한글·영문·공백은 그대로 유지된다" do
        path = repo.write(build_note(title: "오늘 수업 reflection"))
        expect(path.basename.to_s).to eq("오늘 수업 reflection.md")
      end
    end

    context "파일명 충돌" do
      it "같은 경로가 이미 있으면 -2 suffix를 붙인다" do
        repo.write(build_memo)
        path2 = repo.write(build_memo)
        expect(path2.basename.to_s).to eq("2026-05-08_092314-2.md")
      end

      it "두 번 충돌하면 -3 suffix까지 간다" do
        repo.write(build_memo)
        repo.write(build_memo)
        path3 = repo.write(build_memo)
        expect(path3.basename.to_s).to eq("2026-05-08_092314-3.md")
      end
    end
  end

  describe "#read" do
    let(:other_ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZJ") }

    it "Memo 파일을 도메인으로 복원한다" do
      original = build_memo(title: "1교시", tags: Sowing::Domain::ValueObjects::TagSet.new(["수업"]))
      path = repo.write(original)
      restored = repo.read(path)
      expect(restored).to be_a(Sowing::Domain::Memo)
      expect(restored.id).to eq(original.id)
      expect(restored.title).to eq("1교시")
      expect(restored.tags.to_a).to eq(["수업"])
      expect(restored.body).to eq(original.body)
    end

    it "Note 파일을 도메인으로 복원한다 (category·source 포함)" do
      original = build_note(id: other_ulid, title: "정리", source: "교과서")
      path = repo.write(original)
      restored = repo.read(path)
      expect(restored).to be_a(Sowing::Domain::Note)
      expect(restored.category).to eq("lessons")
      expect(restored.source).to eq("교과서")
    end

    it "Record 파일을 도메인으로 복원한다 (promoted_from 포함)" do
      original = build_record(title: "5월", promoted_from: "00_Inbox/x.md")
      path = repo.write(original)
      restored = repo.read(path)
      expect(restored).to be_a(Sowing::Domain::Record)
      expect(restored.promoted_from).to eq("00_Inbox/x.md")
    end

    it "vault 기준 상대 경로도 받는다" do
      repo.write(build_memo)
      restored = repo.read("00_Inbox/2026-05-08_092314.md")
      expect(restored.id).to eq(ulid)
    end

    it "frontmatter에 필수 키가 없으면 ArgumentError" do
      bad = vault_dir.join("00_Inbox/bad.md")
      FileUtils.mkdir_p(bad.dirname)
      File.write(bad, "---\nmode: memo\n---\n\nhi\n")  # id 없음
      expect { repo.read(bad) }.to raise_error(ArgumentError, /id/)
    end

    it "지원하지 않는 mode면 ArgumentError" do
      bad = vault_dir.join("00_Inbox/bad.md")
      FileUtils.mkdir_p(bad.dirname)
      File.write(bad, "---\nid: 01KR1FE1QYH4EEP6RAGR9DJ6ZH\nmode: alien\ncreated_at: '2026-05-08T09:23:14+09:00'\nupdated_at: '2026-05-08T09:23:14+09:00'\n---\n\nhi\n")
      expect { repo.read(bad) }.to raise_error(ArgumentError, /mode/)
    end
  end

  describe "#list" do
    it "지정한 모드의 모든 .md 파일 경로를 정렬해서 반환한다" do
      repo.write(build_memo(created_at: Time.new(2026, 5, 8, 9, 0, 0, "+09:00")))
      repo.write(build_memo(created_at: Time.new(2026, 5, 8, 10, 0, 0, "+09:00")))
      paths = repo.list(mode: :memo)
      expect(paths.size).to eq(2)
      expect(paths.map(&:basename).map(&:to_s))
        .to eq(["2026-05-08_090000.md", "2026-05-08_100000.md"])
    end

    it "디렉토리가 없으면 빈 배열을 반환한다" do
      expect(repo.list(mode: :note)).to eq([])
    end

    it "Note는 카테고리 폴더를 재귀적으로 탐색한다" do
      repo.write(build_note(title: "a", category: "lessons"))
      repo.write(build_note(title: "b", category: "trainings"))
      paths = repo.list(mode: :note)
      expect(paths.size).to eq(2)
      expect(paths.map(&:to_s)).to all(include("/20_Notes/"))
    end
  end

  describe "#delete" do
    it ".sowing/trash/ 아래에 원본 경로를 미러링하여 이동한다" do
      path = repo.write(build_memo)
      trashed = repo.delete(path)

      expect(path).not_to exist
      expect(trashed).to exist
      expect(trashed.to_s).to eq(vault_dir.join(".sowing/trash/00_Inbox/2026-05-08_092314.md").to_s)
    end

    it "휴지통에 이미 같은 이름이 있으면 -2 suffix" do
      path = repo.write(build_memo)
      repo.delete(path)

      path2 = repo.write(build_memo)
      trashed2 = repo.delete(path2)
      expect(trashed2.basename.to_s).to eq("2026-05-08_092314-2.md")
    end

    it "원본 파일이 없으면 Errno::ENOENT" do
      expect { repo.delete(vault_dir.join("00_Inbox/missing.md")) }
        .to raise_error(Errno::ENOENT)
    end
  end

  describe "#update" do
    let(:original) { build_note(title: "원본", category: "lessons") }
    let(:original_path) { repo.write(original) }

    context "같은 path (title·category 모두 동일)" do
      it "atomic 덮어쓰기로 동일 경로에 쓴다 (-2 suffix 없음)" do
        original_path # 생성

        revised = build_note(title: "원본", category: "lessons", body: "수정됨")
        new_path = repo.update(revised, old_path: original_path)

        expect(new_path).to eq(original_path)
        expect(File.read(new_path)).to include("수정됨")
        expect(repo.list(mode: :note).size).to eq(1)
      end
    end

    context "title 변경으로 path가 바뀔 때" do
      it "새 path에 쓰고 옛 파일을 휴지통으로 옮긴다" do
        original_path # 생성

        revised = build_note(title: "수정된 제목", category: "lessons", body: "본문")
        new_path = repo.update(revised, old_path: original_path)

        expect(new_path).to eq(vault_dir.join("20_Notes/lessons/수정된 제목.md"))
        expect(new_path).to exist
        expect(original_path).not_to exist
        expect(vault_dir.join(".sowing/trash/20_Notes/lessons/원본.md")).to exist
      end
    end

    context "category 변경으로 path가 바뀔 때" do
      it "새 카테고리 디렉토리에 쓰고 옛 디렉토리 파일은 휴지통으로" do
        original_path

        revised = build_note(title: "원본", category: "trainings", body: "본문")
        new_path = repo.update(revised, old_path: original_path)

        expect(new_path.to_s).to include("/20_Notes/trainings/원본.md")
        expect(new_path).to exist
        expect(original_path).not_to exist
        expect(vault_dir.join(".sowing/trash/20_Notes/lessons/원본.md")).to exist
      end
    end

    context "old_path 파일이 누락된 경우 (인덱스 정합성 깨진 채 update)" do
      it "새 path에 쓰기는 성공하고 옛 trash 시도는 graceful" do
        # 옛 파일을 강제로 삭제 (trash 안 거치고)
        FileUtils.rm(original_path)

        revised = build_note(title: "원본", category: "lessons", body: "본문")
        expect { repo.update(revised, old_path: original_path) }.not_to raise_error
        expect(File.exist?(original_path)).to be true # 새 파일이 같은 위치에 다시 생성됨
      end
    end
  end

  describe "round-trip 정합성" do
    it "write → read 후 도메인 속성이 모두 일치한다" do
      original = build_memo(
        title: "1교시 메모",
        tags: Sowing::Domain::ValueObjects::TagSet.new(["수업", "1학년"]),
        template: "lesson_reflection"
      )
      path = repo.write(original)
      restored = repo.read(path)

      expect(restored.id).to eq(original.id)
      expect(restored.mode).to eq(original.mode)
      expect(restored.body).to eq(original.body)
      expect(restored.title).to eq(original.title)
      expect(restored.tags.to_a).to eq(original.tags.to_a)
      expect(restored.template).to eq(original.template)
      expect(restored.created_at).to eq(original.created_at)
      expect(restored.updated_at).to eq(original.updated_at)
    end
  end
end
