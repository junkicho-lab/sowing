# frozen_string_literal: true

require "time"

RSpec.describe Sowing::UseCases::DetectStudentGaps do
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 5, 10, 12, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  subject(:use_case) { described_class.new(db: db, clock: clock) }

  before do
    db[:entity_mentions].delete
    db[:entities].delete
  end

  def seed_entity(name:, last_seen_at:, type: "student")
    db[:entities].insert(
      type: type, name: name,
      first_seen_at: "2026-04-01T00:00:00+09:00",
      last_seen_at: last_seen_at,
      mention_count: 1
    )
  end

  describe "#call" do
    it "ROADMAP 검증 — 명단 30명 + 엔티티 → 미언급 7명 정확 식별" do
      # 30명 명단
      roster = (1..30).map { |i| "학생#{i}" }
      # 23명만 최근 4주 내 활성 (= mentioned)
      active = roster.first(23)
      active.each { |name| seed_entity(name: name, last_seen_at: "2026-05-09T10:00:00+09:00") }

      result = use_case.call(class_roster: roster)
      data = result.value!

      expect(data[:roster_size]).to eq(30)
      expect(data[:mentioned_count]).to eq(23)
      expect(data[:unmentioned_count]).to eq(7) # 정확히 7명
      expect(data[:unmentioned]).to eq(roster.last(7))
      expect(data[:gap_ratio]).to be_within(0.001).of(7.0 / 30)
    end

    it "전원 활성 → unmentioned 0" do
      roster = %w[민준 서연 지호]
      roster.each { |n| seed_entity(name: n, last_seen_at: "2026-05-08T10:00:00+09:00") }

      data = use_case.call(class_roster: roster).value!
      expect(data[:unmentioned]).to be_empty
      expect(data[:gap_ratio]).to eq(0.0)
    end

    it "전원 미언급 → unmentioned = roster" do
      roster = %w[민준 서연 지호]
      data = use_case.call(class_roster: roster).value!
      expect(data[:unmentioned]).to eq(roster)
      expect(data[:gap_ratio]).to eq(1.0)
    end

    it "weeks_back 인자 — 5주 전 활성은 4주 기본에서 미언급" do
      roster = %w[옛학생]
      seed_entity(name: "옛학생", last_seen_at: "2026-04-01T10:00:00+09:00") # 5주+ 전

      default_data = use_case.call(class_roster: roster).value!
      expect(default_data[:unmentioned]).to include("옛학생")

      generous_data = use_case.call(class_roster: roster, weeks_back: 8).value!
      expect(generous_data[:mentioned]).to include("옛학생")
    end

    it "Settings.class_roster 자동 로드 (인자 없을 때)" do
      Sowing::Core::Settings.update(class_roster: %w[A B C])
      seed_entity(name: "A", last_seen_at: "2026-05-09T10:00:00+09:00")

      data = use_case.call.value!
      expect(data[:roster_size]).to eq(3)
      expect(data[:mentioned]).to contain_exactly("A")
      expect(data[:unmentioned]).to contain_exactly("B", "C")
    ensure
      Sowing::Core::Settings.update(class_roster: [])
    end

    it "빈 명단 → Failure(:empty_roster)" do
      result = use_case.call(class_roster: [])
      expect(result).to be_failure
      expect(result.failure).to eq(:empty_roster)
    end

    it "Settings 도 명단 도 없으면 Failure(:empty_roster)" do
      Sowing::Core::Settings.update(class_roster: [])
      expect(use_case.call.failure).to eq(:empty_roster)
    end

    it "since (cutoff) ISO8601 반환" do
      roster = %w[민준]
      data = use_case.call(class_roster: roster).value!
      expect(data[:since]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "type=subject/location 의 entities 는 무시 (학생만)" do
      roster = %w[민준]
      # subject 타입에 동명 entity 만들어도 학생 매칭 영향 없음
      seed_entity(name: "민준", type: "subject", last_seen_at: "2026-05-09T10:00:00+09:00")
      data = use_case.call(class_roster: roster).value!
      expect(data[:unmentioned]).to include("민준")
    end

    it "명단 중복 제거 후 처리" do
      roster = %w[민준 민준 서연 서연]
      data = use_case.call(class_roster: roster).value!
      expect(data[:roster_size]).to eq(2)
    end

    it "공백 또는 빈 이름 무시" do
      roster = ["민준", "  ", "", "서연"]
      data = use_case.call(class_roster: roster).value!
      expect(data[:roster_size]).to eq(2)
    end
  end

  describe "결정적 보장 (LLM 미사용 — ROADMAP)" do
    it "같은 입력 → 같은 출력 (반복 호출)" do
      roster = %w[A B C D E]
      seed_entity(name: "B", last_seen_at: "2026-05-09T10:00:00+09:00")
      seed_entity(name: "D", last_seen_at: "2026-05-09T10:00:00+09:00")

      first = use_case.call(class_roster: roster).value!
      second = use_case.call(class_roster: roster).value!
      expect(first).to eq(second)
    end
  end
end
