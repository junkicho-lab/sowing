# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"

# Phase R Stage 4a R4a-T01~T03 — Insight Façade + SynthesisRepo 통합.
RSpec.describe "Sowing::Insight Façade (Stage 4a)" do
  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("insight-spec-")) }
  let(:repo) { Sowing::Insight::SynthesisRepo.new(vault_dir: vault_dir) }

  before do
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete

    Sowing::Insight.repo = repo
    Sowing::Knowledge.record_repo = Sowing::Knowledge::RecordRepo.new(
      vault_repo: Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir),
      index_repo: Sowing::Repositories::IndexRepo.new
    )
  end

  after do
    Sowing::Insight.reset_repo!
    Sowing::Knowledge.reset_repos!
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  # ── 도우미: 직접 synth 파일을 작성 (use case 호출 우회) ──
  def write_synth(type:, target:, title: "샘플 합성", body: "본문 내용", synth_at: Time.now, extras: {})
    synth = Sowing::Insight::Synthesis.new(
      type: type, target: target, title: title, body: body,
      synth_at: synth_at, source_count: 5, extras: extras
    )
    repo.write(synth)
    synth
  end

  describe "SYNTHESIZER_TYPES" do
    it "18 종 정의됨 (17 + self-mirror)" do
      expect(Sowing::Insight::SYNTHESIZER_TYPES.size).to eq(18)
    end

    it "USE_CASE_DISPATCH 가 self-mirror 까지 모두 매핑" do
      Sowing::Insight::SYNTHESIZER_TYPES.each do |t|
        expect(Sowing::Insight::USE_CASE_DISPATCH).to have_key(t)
      end
    end
  end

  describe ".pending / .pending_count" do
    it "Synth 파일 0건 → 0" do
      expect(Sowing::Insight.pending_count).to eq(0)
      expect(Sowing::Insight.pending).to eq([])
    end

    it "여러 type 에 파일 작성 후 합산" do
      write_synth(type: :students, target: "student:김철수")
      write_synth(type: :students, target: "student:이영희")
      write_synth(type: :"self-mirror", target: "self-mirror:daily-2026-05-12",
        extras: {synth_period: "daily", synth_period_date: "2026-05-12"})

      expect(Sowing::Insight.pending_count).to eq(3)
      expect(Sowing::Insight.pending_count(type: :students)).to eq(2)
      expect(Sowing::Insight.pending_count(type: :"self-mirror")).to eq(1)
    end

    it "특정 type 만 필터" do
      write_synth(type: :students, target: "student:김철수")
      write_synth(type: :reflections, target: "semester:2026-1")

      result = Sowing::Insight.pending(type: :students)
      expect(result.size).to eq(1)
      expect(result.first.type).to eq(:students)
    end
  end

  describe ".find" do
    it "type:slug id 로 회수" do
      synth = write_synth(type: :students, target: "student:김철수")
      found = Sowing::Insight.find("students:김철수")
      expect(found).to be_a(Sowing::Insight::Synthesis)
      expect(found.target).to eq("student:김철수")
    end

    it "id format 잘못 → nil" do
      expect(Sowing::Insight.find("nonsense")).to be_nil
    end

    it "존재하지 않으면 nil" do
      expect(Sowing::Insight.find("students:없음")).to be_nil
    end
  end

  describe ".accept" do
    it "Synth 를 Knowledge::Record 로 이전 + 원본 파일 삭제" do
      synth = write_synth(
        type: :students, target: "student:김철수",
        title: "학생 관찰: 김철수", body: "이번 주 김철수는 적극적이었다."
      )
      synth_file = vault_dir.join(".sowing/synth/students/김철수.md")
      expect(synth_file).to exist

      record = Sowing::Insight.accept("students:김철수")

      expect(record).to be_a(Sowing::Knowledge::Record)
      expect(record.title).to eq("학생 관찰: 김철수")
      expect(record.body).to include("적극적이었다")
      # 2026-05-12 — ACCEPT_CATEGORY 가 4축 한국어 라벨로 일원화.
      expect(record.category).to eq("인물") # students → 인물
      expect(synth_file).not_to exist
    end

    it "self-mirror 도 4축 (정체성) category 로 수락" do
      write_synth(type: :"self-mirror", target: "self-mirror:daily-2026-05-12",
        title: "오늘의 거울", body: "본문",
        extras: {synth_period: "daily", synth_period_date: "2026-05-12"})

      record = Sowing::Insight.accept("self-mirror:daily-2026-05-12")
      expect(record.category).to eq("정체성")
    end

    it "없는 id 는 ArgumentError" do
      expect { Sowing::Insight.accept("students:없음") }
        .to raise_error(ArgumentError, /못 찾음/)
    end
  end

  describe ".reject" do
    it "휴지통으로 이동 (영구 삭제 0)" do
      write_synth(type: :students, target: "student:김철수")
      synth_file = vault_dir.join(".sowing/synth/students/김철수.md")
      expect(synth_file).to exist

      trash_path = Sowing::Insight.reject("students:김철수")
      expect(synth_file).not_to exist
      expect(trash_path).to exist
      expect(trash_path.to_s).to include(".sowing/trash")
    end

    it "존재하지 않으면 nil (idempotent 안전)" do
      expect(Sowing::Insight.reject("students:없음")).to be_nil
    end
  end

  describe ".generate (dispatcher)" do
    # 본 spec 은 dispatch 로직만 검증. 실제 use case 동작은 spec/use_cases/ 가 책임.
    it "SYNTHESIZER_TYPES 밖이면 ArgumentError" do
      expect { Sowing::Insight.generate(type: "unknown") }
        .to raise_error(ArgumentError, /type/)
    end

    it "use case Failure 면 GenerationFailed (reason symbol 보존)" do
      stub_const("Sowing::UseCases::TestStubUseCase", Class.new {
        def call(**)
          Dry::Monads::Failure(:test_reason)
        end
      })
      stub_const("Sowing::Insight::USE_CASE_DISPATCH",
        Sowing::Insight::USE_CASE_DISPATCH.merge("students" => :TestStubUseCase))

      expect { Sowing::Insight.generate(type: "students") }
        .to raise_error(Sowing::Insight::GenerationFailed) { |e|
          expect(e.reason).to eq(:test_reason)
          expect(e.type).to eq("students")
        }
    end
  end
end
