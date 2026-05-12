# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::ComputeSynthMetrics do
  let(:tmp_vault) { Pathname.new(Dir.mktmpdir("synth-metrics-spec-")) }
  let(:audit_log) { Sowing::Core::AuditLog.new(vault_dir: tmp_vault) }
  let(:fixed_now) { Time.new(2026, 7, 31, 12, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }

  after { FileUtils.rm_rf(tmp_vault) if tmp_vault.exist? }

  def append_audit(action:, type:, slug:, ts: nil)
    Timecop.freeze(ts || fixed_now) do
      audit_log.append(
        action: action,
        entry_id: (action == :synth_accept) ? "01ACPT00000000000000000001" : "synth:type:#{slug}",
        mode: "record",
        path: ".sowing/synth/#{type}/#{slug}.md"
      )
    end
  end

  describe "#call" do
    subject(:use_case) { described_class.new(audit_log: audit_log, clock: clock) }

    it "Failure(:no_events) — synth_* 이벤트 0건" do
      result = use_case.call
      expect(result).to be_failure
      expect(result.failure).to eq(:no_events)
    end

    it "다른 action (:create 등) 은 카운트 안 함" do
      Timecop.freeze(fixed_now) do
        audit_log.append(action: :create, entry_id: "01CRE00000000000000000001",
          mode: "memo", path: "00_Inbox/test.md")
      end
      result = use_case.call
      expect(result).to be_failure
      expect(result.failure).to eq(:no_events)
    end

    describe "totals 집계" do
      before do
        # students: 5 generate / 3 accept / 1 reject
        5.times { |i| append_audit(action: :synth_generate, type: "students", slug: "학생#{i}") }
        3.times { |i| append_audit(action: :synth_accept, type: "students", slug: "학생#{i}") }
        append_audit(action: :synth_reject, type: "students", slug: "학생4")
      end

      it "generate/accept/reject/pending/acceptance_rate 정확" do
        result = use_case.call
        expect(result).to be_success
        totals = result.value![:totals]

        expect(totals[:generate]).to eq(5)
        expect(totals[:accept]).to eq(3)
        expect(totals[:reject]).to eq(1)
        expect(totals[:decided]).to eq(4)
        expect(totals[:pending]).to eq(1)  # 5 - 4
        expect(totals[:acceptance_rate]).to eq(0.75)  # 3 / 4
      end

      it "event_count + first/last/duration_days 정확" do
        result = use_case.call
        v = result.value!
        expect(v[:event_count]).to eq(9)  # 5 + 3 + 1
        expect(v[:duration_days]).to eq(1)  # 모두 같은 날 시드됨
      end
    end

    describe "by_type 집계 — 6 type 혼합" do
      before do
        # students: 3 gen / 2 acc / 1 rej
        3.times { |i| append_audit(action: :synth_generate, type: "students", slug: "s#{i}") }
        2.times { |i| append_audit(action: :synth_accept, type: "students", slug: "s#{i}") }
        append_audit(action: :synth_reject, type: "students", slug: "s2")
        # reflections: 2 gen / 0 결정
        2.times { |i| append_audit(action: :synth_generate, type: "reflections", slug: "2026-W#{i + 18}") }
        # patterns: 1 gen / 1 acc
        append_audit(action: :synth_generate, type: "patterns", slug: "lessons")
        append_audit(action: :synth_accept, type: "patterns", slug: "lessons")
      end

      it "type 별 카운트·수락률 정확" do
        result = use_case.call
        by_type = result.value![:by_type]

        expect(by_type["students"]).to eq(
          generate: 3, accept: 2, reject: 1, pending: 0,
          acceptance_rate: 2.0 / 3
        )
        expect(by_type["reflections"]).to eq(
          generate: 2, accept: 0, reject: 0, pending: 2,
          acceptance_rate: nil
        )
        expect(by_type["patterns"]).to eq(
          generate: 1, accept: 1, reject: 0, pending: 0,
          acceptance_rate: 1.0
        )
      end
    end

    describe "by_week 집계 (ISO 주)" do
      before do
        append_audit(action: :synth_generate, type: "students", slug: "a",
          ts: Time.new(2026, 5, 4, 9, 0, 0, "+09:00"))   # 2026-W19 (월)
        append_audit(action: :synth_accept, type: "students", slug: "a",
          ts: Time.new(2026, 5, 6, 9, 0, 0, "+09:00"))   # 2026-W19 (수)
        append_audit(action: :synth_generate, type: "reflections", slug: "x",
          ts: Time.new(2026, 5, 11, 9, 0, 0, "+09:00")) # 2026-W20 (월)
        append_audit(action: :synth_reject, type: "reflections", slug: "x",
          ts: Time.new(2026, 5, 13, 9, 0, 0, "+09:00")) # 2026-W20 (수)
      end

      it "주별 카운트 정확 + 시간순" do
        result = use_case.call
        by_week = result.value![:by_week]

        expect(by_week.size).to eq(2)
        expect(by_week[0]).to eq(week: "2026-W19", generate: 1, accept: 1, reject: 0)
        expect(by_week[1]).to eq(week: "2026-W20", generate: 1, accept: 0, reject: 1)
      end
    end

    describe "since/until 필터" do
      before do
        append_audit(action: :synth_generate, type: "students", slug: "a",
          ts: Time.new(2026, 4, 1, 9, 0, 0, "+09:00"))   # 범위 밖 (이전)
        append_audit(action: :synth_generate, type: "students", slug: "b",
          ts: Time.new(2026, 5, 15, 9, 0, 0, "+09:00")) # 범위 안
        append_audit(action: :synth_accept, type: "students", slug: "b",
          ts: Time.new(2026, 5, 20, 9, 0, 0, "+09:00")) # 범위 안
        append_audit(action: :synth_generate, type: "students", slug: "c",
          ts: Time.new(2026, 8, 1, 9, 0, 0, "+09:00"))   # 범위 밖 (이후)
      end

      it "since-until 안의 이벤트만 카운트" do
        result = use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
        v = result.value!

        expect(v[:event_count]).to eq(2)  # 5/15 generate + 5/20 accept
        expect(v[:totals][:generate]).to eq(1)
        expect(v[:totals][:accept]).to eq(1)
      end
    end

    describe "엣지 케이스" do
      it "path 형식 이상한 entry — synth_type='unknown' 그룹" do
        Timecop.freeze(fixed_now) do
          audit_log.append(action: :synth_generate, entry_id: "synth:weird:x",
            mode: "record", path: "weird/path/no-prefix.md")
        end
        result = use_case.call
        v = result.value!
        expect(v[:by_type]).to have_key("unknown")
      end

      it "재생성 시 generate 누적, pending 음수 방지" do
        # 같은 학생 3번 재생성 + 1번 수락 → generate 3, accept 1
        # ts 는 fixed_now 이전이어야 until_t (=fixed_now) 필터를 통과
        base = fixed_now - 3600
        3.times { |i|
          append_audit(action: :synth_generate, type: "students", slug: "민준",
            ts: base + i * 60)
        }
        append_audit(action: :synth_accept, type: "students", slug: "민준",
          ts: base + 1000)

        result = use_case.call
        totals = result.value![:totals]
        expect(totals[:generate]).to eq(3)
        expect(totals[:accept]).to eq(1)
        expect(totals[:pending]).to eq(2)  # 3 - 1, 음수 X
      end
    end
  end
end
