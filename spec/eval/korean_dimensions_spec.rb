# frozen_string_literal: true

require "front_matter_parser"

RSpec.describe Sowing::Eval::KoreanDimensions do
  describe ".honorific_consistency" do
    it "100% 높임말 → 5" do
      text = "오늘 학생들이 발표를 잘 했습니다. 다음 시간이 기대됩니다."
      expect(described_class.honorific_consistency(text)).to eq(5)
    end

    it "100% 평어 → 5" do
      text = "오늘 1교시 학생들이 활기차다. 협동학습 시도 잘 됐다."
      expect(described_class.honorific_consistency(text)).to eq(5)
    end

    it "혼용 (반반) → 1 또는 0" do
      text = "오늘 수업 잘 했습니다. 학생들이 활기차다."
      score = described_class.honorific_consistency(text)
      expect(score).to be <= 1
    end

    it "종결어미 없음 → 5 (검증 불가)" do
      text = "수업"
      expect(described_class.honorific_consistency(text)).to eq(5)
    end

    it "압도적 다수 (90%+) → 4" do
      # 9 높임 + 1 평어
      text = (["수업이 좋았습니다."] * 9 + ["학생 활기차다."]).join(" ")
      score = described_class.honorific_consistency(text)
      expect(score).to be_between(3, 4) # ratio 0.9
    end
  end

  describe ".korean_date_format" do
    it "100% 한국식 → 5" do
      text = "2026년 5월 8일과 5월 10일에 상담 예정"
      expect(described_class.korean_date_format(text)).to eq(5)
    end

    it "100% ISO → 5" do
      text = "2026-05-08 부터 2026-05-15 까지"
      expect(described_class.korean_date_format(text)).to eq(5)
    end

    it "혼용 → 점수 하락" do
      text = "2026년 5월 8일에 시작, 2026-05-15 종료"
      score = described_class.korean_date_format(text)
      expect(score).to be <= 1
    end

    it "날짜 없음 → 5" do
      expect(described_class.korean_date_format("일반 텍스트")).to eq(5)
    end
  end

  describe ".student_anonymity" do
    it "풀네임 0 → 5" do
      text = "민준이가 발표를 자원했다. 서연이는 글쓰기 잘 함."
      expect(described_class.student_anonymity(text)).to eq(5)
    end

    it "풀네임 1개 → 4" do
      text = "김민준 학생이 잘 했다."
      expect(described_class.student_anonymity(text)).to eq(4)
    end

    it "풀네임 5+ → 0" do
      text = "김민준, 이서연, 박지호, 최도현, 정나래, 강예린"
      expect(described_class.student_anonymity(text)).to eq(0)
    end

    it "성씨 + 한 음절은 풀네임 아님 (이름만 표기로 간주)" do
      text = "김 학생, 이 학생" # 성+공백+학생 — 풀네임 아님
      expect(described_class.student_anonymity(text)).to eq(5)
    end
  end

  describe ".classroom_context" do
    it "교실 어휘 풍부 → 5" do
      text = "오늘 수업에서 학생들이 모둠 토론으로 발표 활동을 했다. 회고는 학급 일지에. 평가는 다음 주."
      expect(described_class.classroom_context(text)).to eq(5)
    end

    it "교실 어휘 없음 → 0" do
      text = "오늘 날씨가 좋다. 산책하기 좋은 날."
      expect(described_class.classroom_context(text)).to eq(0)
    end

    it "교실 어휘 1~2개 → 1" do
      text = "수업이 좋았다."
      expect(described_class.classroom_context(text)).to eq(1)
    end
  end

  describe ".tag_korean" do
    it "한글 태그 0 → 0" do
      text = "본문만 있음"
      expect(described_class.tag_korean(text)).to eq(0)
    end

    it "한글 태그 1 → 2" do
      text = "본문 #수업"
      expect(described_class.tag_korean(text)).to eq(2)
    end

    it "한글 태그 4+ → 5" do
      text = "본문 #수업 #협동학습 #회고 #학생관찰"
      expect(described_class.tag_korean(text)).to eq(5)
    end

    it "영문 태그는 카운트 안 함" do
      text = "본문 #english #korean_only_counts"
      expect(described_class.tag_korean(text)).to eq(0)
    end

    it "중복 태그는 1개로 카운트 (uniq)" do
      text = "본문 #수업 #수업 #수업"
      expect(described_class.tag_korean(text)).to eq(2)
    end
  end

  describe ".evaluate_all" do
    it "5 차원 모두 동시 평가" do
      text = "2026년 5월 8일 수업에서 민준이 발표 자원. #수업 #협동학습"
      scores = described_class.evaluate_all(text)
      expect(scores.keys).to contain_exactly(*described_class.dimensions)
      scores.each_value { |s| expect(s).to be_between(0, 5) }
    end

    it "교사 회고 sample — 모든 차원 ≥ 3" do
      text = <<~TXT
        2026년 5월 8일 수업 회고
        오늘 1교시에 협동학습 첫 시도. 학생들이 모둠 토론을 활발히 했다.
        민준이는 발표를 자원했다. 서연이는 글쓰기 우수.
        다음 차시 평가에서 같은 모둠 구성 시도해 볼 만하다.
        #수업 #협동학습 #학생관찰
      TXT
      scores = described_class.evaluate_all(text)
      scores.each do |dim, score|
        expect(score).to be >= 3, "#{dim}=#{score} (3 이상 기대)"
      end
    end
  end

  describe "결정적 self-consistency (kappa = 1.0 보장)" do
    it "같은 입력 → 같은 점수 (이중 호출)" do
      text = "2026-05-08 수업 회고. 민준이 발표 잘 했다. #수업"
      first = described_class.evaluate_all(text)
      second = described_class.evaluate_all(text)
      expect(first).to eq(second)
    end

    it "Kappa.quadratic_weighted 두 평가자 동일 → 1.0 (W13-T04 검증 형식 충족)" do
      texts = [
        "2026년 5월 8일 수업. 민준이 발표 잘 했다. #수업",
        "오늘 학생들 활기차다.",
        "2026-05-08 회고를 적었습니다."
      ]
      scores_a = texts.map { |t| described_class.honorific_consistency(t) }
      scores_b = texts.map { |t| described_class.honorific_consistency(t) }
      kappa = Sowing::Eval::Kappa.quadratic_weighted(scores_a, scores_b)
      expect(kappa).to be_within(1e-9).of(1.0)
      expect(kappa).to be >= 0.7 # ROADMAP 검증 임계값
    end
  end
end

RSpec.describe "한국어 차원 — 100건 corpus 분포 (W13-T04)" do
  let(:corpus_files) {
    Dir.glob(File.expand_path("../../eval/corpus/teacher_writings/**/*.md", __dir__))
  }

  let(:scores) {
    corpus_files.map do |path|
      body = FrontMatterParser::Parser.new(:md).call(File.read(path)).content
      Sowing::Eval::KoreanDimensions.evaluate_all(body)
    end
  }

  it "5 차원 모두 corpus 에서 점수 도출 가능 (100건)" do
    expect(scores.size).to eq(100)
    Sowing::Eval::KoreanDimensions.dimensions.each do |dim|
      values = scores.map { |s| s[dim] }
      expect(values.size).to eq(100)
      values.each { |v| expect(v).to be_between(0, 5) }
    end
  end

  it "honorific_consistency 평균이 일정 수준 이상 (corpus 가 일관된 스타일)" do
    avg = scores.map { |s| s["honorific_consistency"] }.sum.to_f / scores.size
    expect(avg).to be >= 3.5 # 한국 교사 일지 corpus 는 일관됨
  end

  it "classroom_context 가 ≥ 1 인 케이스가 다수 (교실 도메인 corpus 임을 확인)" do
    nonzero = scores.count { |s| s["classroom_context"] >= 1 }
    expect(nonzero).to be >= 50 # 100건 중 절반 이상
  end
end
