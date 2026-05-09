# frozen_string_literal: true

# AGENT_GUIDE.md 완전성 검증 (W9-T05).
# 새 도구 추가 시 가이드도 함께 갱신되도록 contract test.
RSpec.describe "docs/AGENT_GUIDE.md" do
  let(:guide_path) { File.expand_path("../../docs/AGENT_GUIDE.md", __dir__) }
  let(:body) { File.read(guide_path) }

  it "파일 존재 + 비어 있지 않음" do
    expect(File).to exist(guide_path)
    expect(body.length).to be > 1000
  end

  it "Server::TOOLS 의 12개 도구 이름 모두 문서화됨" do
    tool_names = Sowing::MCP::Server::TOOLS.map(&:tool_name)
    tool_names.each do |name|
      expect(body).to include(name), "#{name} 가 AGENT_GUIDE.md 에 누락"
    end
  end

  it "도구 카테고리 3종 (Sensors / Actuators / Analytics) 모두 명시" do
    expect(body).to match(/Sensors.*read-only/i)
    expect(body).to match(/Actuators.*write/i)
    expect(body).to match(/Analytics/i)
  end

  it "Claude Desktop 설정 JSON 블록 포함" do
    expect(body).to include("claude_desktop_config.json")
    expect(body).to match(/"mcpServers".*"sowing"/m)
  end

  it "Codex / Continue.dev / Zed 설정 안내 포함" do
    %w[Codex Continue.dev Zed].each do |client|
      expect(body).to include(client), "#{client} 설정 누락"
    end
  end

  it "자주 쓰는 프롬프트 5종 이상" do
    # "### 1." ~ "### 5." 헤더 패턴
    prompt_count = body.scan(/^### \d+\.\s/).size
    expect(prompt_count).to be >= 5
  end

  it "안전한 사용 패턴 섹션 (audit log + 거부 항목)" do
    expect(body).to include("audit")
    expect(body).to include("ADR-013")
    expect(body).to match(/❌.*챗봇|❌.*자율|❌.*의인화/)
  end

  it "Troubleshooting 섹션 포함" do
    expect(body).to match(/Troubleshooting|문제\s*해결/i)
    expect(body).to include("SOWING_VAULT")
  end

  it "Phase 10+ 다음 단계 미리보기 — 거짓 광고 안 함" do
    expect(body).to match(/Phase 10|Phase 11|synthesize/i)
    # Phase 11+ 도구는 아직 미구현 — "예정" 명시 필수
    expect(body).to match(/예정|계획|Phase 1[01]/)
  end

  it "background.md / EVALUATION.md / DECISIONS.md / ROADMAP.md 교차 참조" do
    %w[ROADMAP DECISIONS EVALUATION background].each do |doc|
      expect(body).to include(doc), "#{doc} 참조 누락"
    end
  end
end
