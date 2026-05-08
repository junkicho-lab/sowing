# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::Repositories::TemplateRepo do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("template-repo-spec-")) }
  let(:system_dir) { Pathname.new(Dir.mktmpdir("template-system-spec-")) }
  let(:fixed_now) { Time.new(2026, 5, 8, 14, 23, 14, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  # 단위 테스트는 시스템 템플릿을 격리 (실제 templates/ 영향 차단).
  let(:repo) { described_class.new(vault_dir: vault_dir, system_dir: system_dir, clock: clock) }

  after do
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
    FileUtils.rm_rf(system_dir) if system_dir.exist?
  end

  describe "#list / #find" do
    it "templates 디렉토리 없으면 빈 배열" do
      expect(repo.list).to eq([])
    end

    it "*.md만 슬러그 정렬로 반환 (다른 확장자 무시)" do
      FileUtils.mkdir_p(vault_dir.join("templates"))
      File.write(vault_dir.join("templates/회고.md"), "회고 본문")
      File.write(vault_dir.join("templates/lesson-reflection.md"), "lesson")
      File.write(vault_dir.join("templates/skipme.txt"), "ignored")

      slugs = repo.list.map(&:slug)
      expect(slugs).to eq(%w[lesson-reflection 회고])
    end

    it "find으로 단일 조회 — 없으면 nil" do
      FileUtils.mkdir_p(vault_dir.join("templates"))
      File.write(vault_dir.join("templates/수업회고.md"), "본문")

      expect(repo.find("수업회고").content).to eq("본문")
      expect(repo.find("없는템플릿")).to be_nil
    end
  end

  describe "#save" do
    it "신규 템플릿 생성 + Template 반환" do
      template = repo.save(slug: "회고", content: "오늘은 {{date}}")
      expect(template.slug).to eq("회고")
      expect(vault_dir.join("templates/회고.md").read).to eq("오늘은 {{date}}")
    end

    it "기존 템플릿 덮어쓰기 (원자적)" do
      repo.save(slug: "회고", content: "v1")
      repo.save(slug: "회고", content: "v2")
      expect(repo.find("회고").content).to eq("v2")
    end

    it "유효하지 않은 슬러그는 ArgumentError" do
      expect { repo.save(slug: "../etc/passwd", content: "x") }.to raise_error(ArgumentError)
      expect { repo.save(slug: "with space", content: "x") }.to raise_error(ArgumentError)
      expect { repo.save(slug: "", content: "x") }.to raise_error(ArgumentError)
      expect { repo.save(slug: "a" * 81, content: "x") }.to raise_error(ArgumentError)
    end

    it "한글/영문/숫자/하이픈/언더스코어 슬러그 허용" do
      %w[수업회고 lesson_reflection 2026-Q2 abc123].each do |slug|
        expect { repo.save(slug: slug, content: "x") }.not_to raise_error
      end
    end
  end

  describe "system + user 두 디렉토리 (W6-T05)" do
    it "system 템플릿이 list에 포함되며 source: :system 마킹" do
      File.write(system_dir.join("기본수업.md"), "기본 콘텐츠")
      list = repo.list
      expect(list.map(&:slug)).to include("기본수업")
      expect(list.find { |t| t.slug == "기본수업" }.source).to eq(:system)
    end

    it "user override — 같은 slug면 user 우선" do
      File.write(system_dir.join("회고.md"), "기본 v")
      FileUtils.mkdir_p(vault_dir.join("templates"))
      File.write(vault_dir.join("templates/회고.md"), "사용자 v")

      template = repo.find("회고")
      expect(template.content).to eq("사용자 v")
      expect(template.source).to eq(:user)
    end

    it "user에만 있으면 source: :user" do
      FileUtils.mkdir_p(vault_dir.join("templates"))
      File.write(vault_dir.join("templates/내것.md"), "사용자만")
      expect(repo.find("내것").source).to eq(:user)
    end

    it "save는 system이 있어도 항상 user_dir로" do
      File.write(system_dir.join("회고.md"), "기본")
      template = repo.save(slug: "회고", content: "내가 덮어씀")
      expect(template.source).to eq(:user)
      expect(template.path.to_s).to include(vault_dir.to_s)
      expect(repo.find("회고").content).to eq("내가 덮어씀")
    end
  end

  describe "#render — 단순 {{key}} 치환" do
    it "default_context의 date/time/date_korean 자동 채움" do
      out = repo.render("작성일: {{date}} ({{date_korean}}), 시각 {{time}}")
      expect(out).to include("작성일: 2026-05-08")
      expect(out).to include("2026년 5월 8일 금요일")
      expect(out).to include("시각 14:23")
    end

    it "year/month/day는 zero-padded month/day" do
      out = repo.render("{{year}}-{{month}}-{{day}}")
      expect(out).to eq("2026-05-08")
    end

    it "사용자 컨텍스트가 default보다 우선 (override)" do
      out = repo.render("이름: {{user}} / 날짜: {{date}}", user: "김선생", date: "2099-01-01")
      expect(out).to eq("이름: 김선생 / 날짜: 2099-01-01")
    end

    it "알 수 없는 키는 원문 유지 (정보 보존)" do
      out = repo.render("{{unknown_key}} {{date}}")
      expect(out).to start_with("{{unknown_key}}")
      expect(out).to include("2026-05-08")
    end

    it "공백 허용 — {{ key }} 도 매칭" do
      out = repo.render("{{ date }}")
      expect(out).to eq("2026-05-08")
    end

    it "치환 대상 없는 평문은 그대로" do
      expect(repo.render("그냥 텍스트")).to eq("그냥 텍스트")
    end

    it "키 기호 string·symbol 모두 동작" do
      expect(repo.render("{{x}}", "x" => "string")).to eq("string")
      expect(repo.render("{{x}}", x: "symbol")).to eq("symbol")
    end
  end
end
