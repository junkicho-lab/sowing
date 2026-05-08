# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::Repositories::TemplateRepo do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("template-repo-spec-")) }
  let(:fixed_now) { Time.new(2026, 5, 8, 14, 23, 14, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  let(:repo) { described_class.new(vault_dir: vault_dir, clock: clock) }

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

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
