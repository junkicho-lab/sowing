# frozen_string_literal: true

# Phase R Stage 3 R3-T02 — Knowledge::Plan 도메인 (옛 Domain::Plan 흡수 + 4축).
RSpec.describe Sowing::Knowledge::Plan do
  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:created_at) { Time.new(2026, 5, 12, 9, 0, 0, "+09:00") }

  def build(**overrides)
    described_class.new(
      id: ulid, title: "1교시 수업 준비", body: "본문",
      period: :daily, plan_date: "2026-05-12",
      created_at: created_at, **overrides
    )
  end

  describe ".new" do
    context "필수 인자만" do
      subject(:plan) { build }

      it "Plan 인스턴스 생성" do
        expect(plan).to be_a(described_class)
      end

      it "mode 는 :plan" do
        expect(plan.mode).to eq(:plan)
      end

      it "done 기본값 false" do
        expect(plan.done).to be(false)
      end

      it "subject 기본값 nil" do
        expect(plan.subject).to be_nil
      end

      it "frozen 불변" do
        expect(plan).to be_frozen
      end
    end

    context "period 5종 모두 허용" do
      described_class::PERIODS.each do |p|
        it "period: #{p.inspect}" do
          expect(build(period: p).period).to eq(p)
        end
      end
    end

    context "period 5축 밖이면 거부" do
      it ":random 거부" do
        expect { build(period: :random) }.to raise_error(ArgumentError, /period/)
      end
    end

    context "subject 4축" do
      described_class::SUBJECTS.each do |axis|
        it "subject: #{axis.inspect} 허용" do
          expect(build(subject: axis).subject).to eq(axis)
        end
      end

      it "SUBJECTS 는 Capture::Item::SUBJECTS 와 동일 (DRY)" do
        expect(described_class::SUBJECTS).to eq(Sowing::Capture::Item::SUBJECTS)
      end

      it "임의 Symbol 거부" do
        expect { build(subject: :random) }.to raise_error(ArgumentError, /subject/)
      end
    end

    context "done 토글" do
      it "true 입력 → true" do
        expect(build(done: true).done).to be(true)
      end

      it "truthy 값은 boolean coerce (!! 연산)" do
        expect(build(done: "yes").done).to be(true)
        expect(build(done: 0).done).to be(true) # Ruby 의 0 는 truthy
      end
    end

    context "validation" do
      it "title 은 필수 String" do
        expect {
          described_class.new(id: ulid, title: nil, body: "x",
            period: :daily, plan_date: "2026-05-12", created_at: created_at)
        }.to raise_error(ArgumentError, /title/)
      end

      it "plan_date 는 필수 String" do
        expect {
          described_class.new(id: ulid, title: "t", body: "x",
            period: :daily, plan_date: nil, created_at: created_at)
        }.to raise_error(ArgumentError, /plan_date/)
      end
    end
  end

  describe "#to_frontmatter" do
    it "period·plan_date·done 키 포함" do
      fm = build(period: :weekly, plan_date: "2026-W19", done: true).to_frontmatter
      expect(fm["period"]).to eq("weekly")
      expect(fm["plan_date"]).to eq("2026-W19")
      expect(fm["done"]).to be(true)
    end

    it "subject nil 이면 .compact 로 제외" do
      expect(build.to_frontmatter).not_to have_key("subject")
    end

    it "subject 있으면 String 직렬화" do
      expect(build(subject: :identity).to_frontmatter["subject"]).to eq("identity")
    end

    it "mode 는 'plan'" do
      expect(build.to_frontmatter["mode"]).to eq("plan")
    end
  end
end
