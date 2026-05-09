#!/usr/bin/env ruby
# frozen_string_literal: true

# eval 코퍼스 자동 생성기 (W13-T01).
#
# 시드: hand_crafted/ 의 케이스 + templates/samples/ 의 12 시드
# 변형: 학생 이름 / 과목 / 카테고리 / 날짜 치환
# 결과: eval/corpus/teacher_writings/generated/ 에 90건 작성 → 합 100건
#
# 한계 (의도적):
# - 단순 치환이라 깊은 의미 변형은 없음. 정량 검증의 base 만 제공.
# - 진짜 평가 품질은 hand_crafted 케이스에서 LLM-judge 카파(W13-T02)로 측정.
#
# 사용:
#   bundle exec ruby eval/scripts/generate_corpus.rb
#
# 멱등 — 기존 generated/ 비우고 재생성.

require "fileutils"
require "json"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
HAND_CRAFTED_DIR = File.join(ROOT, "eval/corpus/teacher_writings/hand_crafted")
GENERATED_DIR = File.join(ROOT, "eval/corpus/teacher_writings/generated")
SAMPLES_DIR = File.join(ROOT, "templates/samples")

# 변형 풀
NAMES = %w[지호 윤아 도현 나래 서윤 시우 하준 예린 채원 우진 다은 시원 건우 가온].freeze
SUBJECTS = %w[국어 수학 사회 과학 영어 도덕 음악 미술 체육 실과].freeze
CATEGORIES = %w[lessons trainings books meetings].freeze
LOCATIONS = %w[교실 도서관 운동장 강당 음악실 미술실 컴퓨터실 과학실].freeze

# 변형 매트릭스 — 어떤 hand_crafted 시드에서 몇 개 generated 만들지.
# 합계 89 = 100 - 11 hand_crafted (ent×3 + dig×2 + gap + ref + con×2 + gen×2).
GENERATION_PLAN = {
  "ent-001" => 14,
  "ent-002" => 12,
  "ent-003" => 5,  # 빈 entity 케이스 — 변형 적게
  "dig-001" => 10,
  "dig-002" => 8,
  "gap-001" => 10,
  "ref-001" => 10,
  "con-001" => 10,
  "con-002" => 5,
  "gen-001" => 5
}.freeze

# 의사난수 시드 — 멱등 보장.
RNG = Random.new(20260510)

def parse_seed(path)
  raw = File.read(path, encoding: "UTF-8")
  return nil unless raw =~ /\A---\n(.*?)\n---\n(.*)\z/m
  {
    front_matter: YAML.safe_load(Regexp.last_match(1), permitted_classes: [Symbol], aliases: true),
    body: Regexp.last_match(2)
  }
end

def variant_pair(pool)
  a, b = pool.sample(2, random: RNG)
  [a, b]
end

def transform(seed, idx, prefix)
  fm = seed[:front_matter].dup
  body = seed[:body].dup

  # 학생 이름 치환 — body 에 등장하는 흔한 이름 → 새 이름 (모든 occurrence).
  %w[민준 서연].each do |original|
    next unless body.include?(original)
    replacement = NAMES.sample(random: RNG)
    body = body.gsub(original, replacement)
    # expected_output 도 students 배열에 있으면 치환
    if fm["expected_output"].is_a?(Hash) && fm["expected_output"]["students"].is_a?(Array)
      fm["expected_output"]["students"] = fm["expected_output"]["students"].map { |s| (s == original) ? replacement : s }
    end
  end

  # 과목 치환 (entity_extraction / general 일부에서)
  if seed[:front_matter]["task"] == "entity_extraction"
    %w[수학 국어 도덕].each do |original|
      next unless body.include?(original)
      replacement = (SUBJECTS - [original]).sample(random: RNG)
      body = body.gsub(original, replacement)
      if fm["expected_output"].is_a?(Hash) && fm["expected_output"]["subjects"].is_a?(Array)
        fm["expected_output"]["subjects"] = fm["expected_output"]["subjects"].map { |s| (s == original) ? replacement : s }
      end
    end
  end

  # case_id 갱신
  fm["case_id"] = format("%s-%03d", prefix, idx)
  fm["hand_crafted"] = false
  fm["notes"] = (fm["notes"] || "") + " (auto-generated variant)"

  serialize(fm, body)
end

def serialize(front_matter, body)
  yaml = YAML.dump(front_matter).delete_prefix("---\n")
  "---\n#{yaml}---\n#{body}"
end

def main
  FileUtils.rm_rf(GENERATED_DIR)
  FileUtils.mkdir_p(GENERATED_DIR)

  total = 0
  GENERATION_PLAN.each do |seed_id, count|
    seed_path = File.join(HAND_CRAFTED_DIR, "#{seed_id}.md")
    abort "시드 누락: #{seed_id}.md" unless File.exist?(seed_path)

    seed = parse_seed(seed_path)
    abort "frontmatter 파싱 실패: #{seed_id}" if seed.nil?

    prefix = seed_id.split("-").first
    count.times do |i|
      out = transform(seed, total + 1, "#{prefix}-gen")
      out_path = File.join(GENERATED_DIR, "#{prefix}-gen-#{format("%03d", total + 1)}.md")
      File.write(out_path, out)
      total += 1
    end
  end

  hand_crafted_count = Dir.glob(File.join(HAND_CRAFTED_DIR, "*.md")).size
  puts "✅ generated #{total}건 작성 (총 hand_crafted #{hand_crafted_count} + generated #{total} = #{hand_crafted_count + total}건)"
end

main if __FILE__ == $PROGRAM_NAME
