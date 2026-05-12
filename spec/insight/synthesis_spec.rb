# frozen_string_literal: true

require "yaml"

# Phase R Stage 4a R4a-T01 — Insight::Synthesis 도메인.
RSpec.describe Sowing::Insight::Synthesis do
  let(:synth_at) { Time.new(2026, 5, 12, 9, 0, 0, "+09:00") }

  def build(**overrides)
    described_class.new(
      type: :students,
      target: "student:김철수",
      title: "학생 관찰: 김철수",
      body: "이번 주 김철수는 ...",
      synth_at: synth_at,
      **overrides
    )
  end

  describe ".new" do
    context "필수 인자만" do
      subject(:synth) { build }

      it "Synthesis 인스턴스 생성" do
        expect(synth).to be_a(described_class)
      end

      it "status 는 :pending (ADR-013 — 유일 상태)" do
        expect(synth.status).to eq(:pending)
      end

      it "frozen 불변" do
        expect(synth).to be_frozen
        expect(synth.body).to be_frozen
      end

      it "source_count 기본 0" do
        expect(synth.source_count).to eq(0)
      end

      it "model 기본 nil (deterministic 모드)" do
        expect(synth.model).to be_nil
      end
    end

    context "type 검증" do
      Sowing::Insight::SYNTHESIZER_TYPES.first(5).each do |t|
        it "type: #{t.inspect} 허용" do
          expect(build(type: t.to_sym).type).to eq(t.to_sym)
        end
      end

      it "self-mirror 허용 (17th 합성기)" do
        s = build(type: :"self-mirror", target: "self-mirror:daily-2026-05-12")
        expect(s.type).to eq(:"self-mirror")
      end

      it "SYNTHESIZER_TYPES 밖 거부" do
        expect { build(type: :unknown_type) }
          .to raise_error(ArgumentError, /type/)
      end
    end

    context "타입 검증" do
      it "target 은 String 필수" do
        expect { build(target: nil) }.to raise_error(ArgumentError, /target/)
      end

      it "body 는 String 필수" do
        expect { build(body: nil) }.to raise_error(ArgumentError, /body/)
      end

      it "synth_at 은 Time 필수" do
        expect { build(synth_at: "2026-05-12") }.to raise_error(ArgumentError, /synth_at/)
      end
    end
  end

  describe "#id" do
    it "type + target slug 결합" do
      synth = build(type: :students, target: "student:김철수")
      expect(synth.id).to eq("students:김철수")
    end

    it "self-mirror 의 daily 키" do
      synth = build(type: :"self-mirror", target: "self-mirror:daily-2026-05-12")
      expect(synth.id).to eq("self-mirror:daily-2026-05-12")
    end
  end

  describe "#recent?" do
    let(:now) { Time.new(2026, 5, 12, 9, 0, 0, "+09:00") }

    it "7일 이내 → true" do
      synth = build(synth_at: now - 3 * 86_400)
      expect(synth.recent?(now: now)).to be(true)
    end

    it "7일 초과 → false" do
      synth = build(synth_at: now - 10 * 86_400)
      expect(synth.recent?(now: now)).to be(false)
    end

    it "days 인자로 윈도우 조정" do
      synth = build(synth_at: now - 30 * 86_400)
      expect(synth.recent?(now: now, days: 60)).to be(true)
    end
  end

  describe "#to_markdown" do
    subject(:synth) {
      build(
        type: :"self-mirror",
        target: "self-mirror:daily-2026-05-12",
        source_count: 25,
        model: "claude-haiku-4-5-20251001",
        extras: {synth_period: "daily", synth_period_date: "2026-05-12"}
      )
    }

    it "옵시디언 호환 마크다운 (frontmatter + 본문)" do
      md = synth.to_markdown
      expect(md).to start_with("---\n")
      expect(md).to include("is_synth: true")
      expect(md).to include("synth_target: self-mirror:daily-2026-05-12")
      expect(md).to include("synth_source_count: 25")
      expect(md).to include("synth_model: claude-haiku-4-5-20251001")
    end

    it "extras 키 (type-specific) 도 frontmatter 에 포함" do
      md = synth.to_markdown
      expect(md).to include("synth_period: daily")
      expect(md).to include("synth_period_date: '2026-05-12'") # YAML quoting
    end

    it "model nil 이면 synth_model 키 제외 (deterministic)" do
      md = build(model: nil).to_markdown
      expect(md).not_to include("synth_model")
    end

    it "YAML round-trip 가능" do
      md = synth.to_markdown
      _, fm_str, body = md.split(/^---\n/, 3)
      fm = YAML.safe_load(fm_str, permitted_classes: [Time, Symbol])
      expect(fm["is_synth"]).to be(true)
      expect(fm["synth_target"]).to eq("self-mirror:daily-2026-05-12")
      expect(body.strip).to start_with("# ")
    end
  end
end
