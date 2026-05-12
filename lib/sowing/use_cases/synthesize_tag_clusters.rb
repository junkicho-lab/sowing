# frozen_string_literal: true

require "dry/monads"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 태그 클러스터 합성 — 자주 함께 등장하는 태그들 → 주제 그룹 발견 (확장 합성기 #7).
    #
    # "내가 무엇에 대해 자주 쓰는가" 자기 인식 도구.
    # entry_tags 테이블 위에 얹는 발견 도구. 사용자가 의식하지 못한 패턴 발견.
    #
    # 알고리즘 (결정적 — Jaccard 유사도 + greedy 클러스터링):
    #   1. 모든 태그 페어 (a, b) 의 co-occurrence 카운트
    #   2. Jaccard = |A ∩ B| / |A ∪ B|
    #   3. 페어 Jaccard ≥ JACCARD_THRESHOLD 이면 같은 클러스터로 union-find merge
    #   4. 각 클러스터의 대표 entries (mention 빈도 상위) 함께 표시
    #
    # 한계 인정 (자율 판단 0):
    #   - 클러스터에 *주제 라벨* 자동 부여는 LLM 모드만. 결정적은 태그 목록만.
    #   - 같은 태그가 여러 클러스터에 들어가지 않음 (단순 union)
    #
    # 저장 위치: vault/.sowing/synth/tag-clusters/topics.md (단일 파일, 누적 갱신)
    class SynthesizeTagClusters
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/tag-clusters"
      MIN_TAG_FREQ = 2          # 1번만 쓰인 태그는 클러스터링 가치 없음
      MIN_PAIR_COUNT = 2        # co-occurrence 최소 (noise 제거)
      JACCARD_THRESHOLD = 0.3   # 30% 이상 겹치면 같은 클러스터
      TOP_REPRESENTATIVES = 3   # 클러스터당 대표 entries 수
      MAX_CLUSTERS = 20         # 한 화면 의미

      def initialize(
        db: nil,
        vault_dir: nil,
        safe_writer: nil,
        llm_backend: nil,
        clock: Time
      )
        @db = db || Core::DB.connection
        @vault_dir = Pathname.new((vault_dir || Core::Paths.vault_dir).to_s).expand_path
        @safe_writer = safe_writer || Core::Filesystem::SafeWriter.new
        @llm_backend = llm_backend
        @clock = clock
      end

      # @return [Result] Success(Pathname) | Failure(:no_tags | :no_clusters)
      def call
        # tag_id → entry_ids set
        tag_to_entries = {}
        tag_names = {}
        @db[:tags].all.each { |t| tag_names[t[:id]] = t[:name] }
        @db[:entry_tags].all.each do |row|
          tag_to_entries[row[:tag_id]] ||= Set.new
          tag_to_entries[row[:tag_id]] << row[:entry_id]
        end

        # 빈도 ≥ MIN_TAG_FREQ 만 클러스터링 후보
        candidate_tags = tag_to_entries.select { |_tid, entries| entries.size >= MIN_TAG_FREQ }
        return Failure(:no_tags) if candidate_tags.size < 2

        # 페어 jaccard 계산
        pairs = compute_pairs(candidate_tags)
        return Failure(:no_clusters) if pairs.empty?

        # union-find 클러스터링
        clusters = cluster_pairs(pairs, candidate_tags.keys)
        clusters = clusters.select { |c| c.size >= 2 }.first(MAX_CLUSTERS)
        return Failure(:no_clusters) if clusters.empty?

        cluster_meta = clusters.map { |tids| build_cluster_meta(tids, tag_names, tag_to_entries) }

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(cluster_meta)
          }
        else
          synthesize_deterministic(cluster_meta)
        end

        target = vault_target
        content = build_full_content(body, cluster_meta)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def compute_pairs(candidate_tags)
        pairs = []
        keys = candidate_tags.keys
        keys.each_with_index do |a, i|
          (i + 1...keys.size).each do |j|
            b = keys[j]
            entries_a = candidate_tags[a]
            entries_b = candidate_tags[b]
            intersection = (entries_a & entries_b).size
            next if intersection < MIN_PAIR_COUNT
            union = (entries_a | entries_b).size
            jaccard = intersection.to_f / union
            next if jaccard < JACCARD_THRESHOLD
            pairs << {a: a, b: b, jaccard: jaccard, intersection: intersection, union: union}
          end
        end
        pairs
      end

      # union-find — 페어 jaccard 가 threshold 넘으면 같은 클러스터.
      def cluster_pairs(pairs, tag_ids)
        parent = {}
        tag_ids.each { |t| parent[t] = t }

        find = lambda { |t|
          while parent[t] != t
            parent[t] = parent[parent[t]]
            t = parent[t]
          end
          t
        }

        union = lambda { |a, b|
          ra = find.call(a)
          rb = find.call(b)
          parent[ra] = rb if ra != rb
        }

        pairs.each { |p| union.call(p[:a], p[:b]) }

        groups = Hash.new { |h, k| h[k] = [] }
        tag_ids.each { |t| groups[find.call(t)] << t }
        groups.values.sort_by { |g| -g.size }
      end

      def build_cluster_meta(tag_ids, tag_names, tag_to_entries)
        all_entry_ids = tag_ids.flat_map { |tid| tag_to_entries[tid].to_a }
        # entry id 빈도 — 클러스터 안의 태그 모두 가진 entry 가 대표
        entry_freq = all_entry_ids.tally
        top_entry_ids = entry_freq.sort_by { |id, n| [-n, id] }.first(TOP_REPRESENTATIVES).map(&:first)

        # 대표 entries 의 path/title 조회
        representative_rows = @db[:entries]
          .where(id: top_entry_ids)
          .order(:created_at)
          .all

        {
          tag_ids: tag_ids,
          tag_names: tag_ids.map { |tid| tag_names[tid] }.sort,
          unique_entry_count: tag_ids.flat_map { |tid| tag_to_entries[tid].to_a }.uniq.size,
          representatives: representative_rows
        }
      end

      def synthesize_deterministic(clusters)
        lines = []
        lines << "## 🏷️ 태그 클러스터 (#{clusters.size}개 그룹, jaccard ≥ #{JACCARD_THRESHOLD})"
        lines << ""
        lines << "_자주 함께 등장한 태그들. \"내가 무엇에 대해 자주 쓰는가\" 자기 인식 도구._"
        lines << "_각 그룹의 *주제 라벨* 부여는 LLM 모드에서. 결정적은 태그 목록 + 대표 entries 만._"
        lines << ""

        clusters.each_with_index do |c, i|
          lines << "### [#{i + 1}] #{c[:tag_names].size}개 태그 그룹"
          lines << ""
          lines << "**태그**: " + c[:tag_names].map { |t| "##{t}" }.join(" · ")
          lines << ""
          lines << "고유 entries: #{c[:unique_entry_count]}건"
          lines << ""
          if c[:representatives].any?
            lines << "**대표 entries** (이 그룹의 태그를 가장 많이 가진 #{c[:representatives].size}건):"
            c[:representatives].each do |row|
              title = row[:title].to_s.empty? ? "(제목 없음)" : row[:title]
              lines << "- #{row[:created_at].to_s[0, 10]} #{mode_icon(row[:mode])} [[#{row[:path]}]] — #{title}"
            end
            lines << ""
          end
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (Jaccard 유사도 + union-find 클러스터링)._"
        lines << "_각 그룹의 의미·라벨은 LLM 모드에서. 같은 태그가 여러 그룹에 들어가지 않습니다 (단순 union)._"
        lines.join("\n")
      end

      def mode_icon(mode)
        case mode.to_s
        when "memo" then "💭"
        when "note" then "📝"
        when "record" then "📖"
        else "·"
        end
      end

      def synthesize_via_llm(clusters)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(clusters)
        ).to_s.strip
      rescue
        synthesize_deterministic(clusters)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사의 태그 모음에서 의미 있는 *주제 그룹* 을 발견합니다.
          입력은 결정적으로 클러스터링된 태그 그룹 + 각 그룹의 대표 entries.
          톤: 발견·궁금증. 단정 X. 본문에 없는 사실 만들기 금지.

          출력 마크다운 (각 그룹당):
          ### [#] 그룹 라벨 (제안)
          - **태그**: ##태그1 #태그2 ...
          - **주제**: 1~2 문장으로 의미 해석 (제안)
          - **자기 발견 질문**: "이 주제에 대해 N건 썼다 — 무엇을 발견하는가?" 같은 질문

          마지막에:
          ## 💡 메타-관찰
          - 전체 클러스터 분포에서 보이는 자기 글쓰기 패턴 1~2 문장

          분량: 그룹당 80~150자.
        TXT
      end

      def llm_user_prompt(clusters)
        list = clusters.map.with_index { |c, i|
          rep = c[:representatives].first(2).map { |r| r[:title].to_s.empty? ? r[:path] : r[:title] }.join(" / ")
          "[#{i + 1}] 태그(#{c[:tag_names].size}): #{c[:tag_names].join(", ")} | 고유 entries #{c[:unique_entry_count]} | 대표: #{rep}"
        }.join("\n")
        "# 태그 그룹 #{clusters.size}개\n\n#{list}\n"
      end

      def build_full_content(body, clusters)
        all_tags = clusters.flat_map { |c| c[:tag_names] }.sort.uniq
        fm = {
          "is_synth" => true,
          "synth_target" => "clusters:topics",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => clusters.size,
          "synth_jaccard_threshold" => JACCARD_THRESHOLD,
          "synth_min_pair_count" => MIN_PAIR_COUNT,
          "synth_clustered_tags" => all_tags,
          "synth_total_unique_entries" => clusters.sum { |c| c[:unique_entry_count] },
          "synth_model" => synth_model_label,
          "title" => "태그 클러스터: 주제 그룹"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 태그 클러스터: 주제 그룹\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target
        @vault_dir.join(SYNTH_DIR, "topics.md")
      end
    end
  end
end
