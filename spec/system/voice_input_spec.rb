# frozen_string_literal: true

require "rack/test"

# Phase 13 W26-T02 — 음성 입력 (Web Speech API).
# 실제 음성 인식은 브라우저 API 라 RSpec 으로 검증 불가 — markup·a11y·
# 클라이언트 코드 존재만 spec. 실 동작은 manual 캡쳐로 확인.
#
# ADR 영향:
# - ADR-009 (로컬-first): Web Speech API 는 Google 서버 경유.
#   안내 hint 에 명시 ("인터넷 필요"). Whisper.cpp 로컬 PoC 는 W26-T02b 예정.
# - ADR-013 (자율 mutation 0): 인식 결과를 textarea 에 채우기만 함.
#   사용자 확인·편집·저장 클릭 없이는 정식 메모 안 됨.
RSpec.describe "음성 입력 (Phase 13 W26-T02)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before { header "Host", "127.0.0.1" }

  describe "빠른 메모 모달의 음성 영역" do
    it "voice button + 라벨 + hint 노출 (hidden default — JS 가 표시)" do
      get "/"
      expect(last_response.body).to include('data-quick-memo-target="voice"')
      expect(last_response.body).to include('data-quick-memo-target="voiceBtn"')
      expect(last_response.body).to include('data-quick-memo-target="voiceLabel"')
    end

    it "음성 입력 라벨 + 시작 aria-label" do
      get "/"
      expect(last_response.body).to include("🎙")
      expect(last_response.body).to include("음성 입력")
      expect(last_response.body).to include('aria-label="음성 입력 시작"')
    end

    it "ADR-009 안내 — 인터넷 필요 + Whisper.cpp 후속 명시" do
      get "/"
      expect(last_response.body).to include("ko-KR")
      expect(last_response.body).to include("Chrome/Edge")
      expect(last_response.body).to include("인터넷 필요")
      expect(last_response.body).to include("Whisper.cpp")
      expect(last_response.body).to include("W26-T02b")
    end

    it "toggleVoice action 바인딩 — Stimulus" do
      get "/"
      expect(last_response.body).to include('click->quick-memo#toggleVoice')
    end
  end

  describe "Stimulus controller 코드 — 클라이언트 자산" do
    let(:js) { File.read(File.join(Sowing.root, "public/js/controllers/quick_memo_controller.js")) }

    it "SpeechRecognition feature detection" do
      expect(js).to include("window.SpeechRecognition")
      expect(js).to include("window.webkitSpeechRecognition")
    end

    it "한국어 (ko-KR) 명시" do
      expect(js).to include('"ko-KR"')
    end

    it "interimResults + continuous — 실시간 표시" do
      expect(js).to include("interimResults = true")
      expect(js).to include("continuous = true")
    end

    it "ADR-013 — 자동 저장 X, textarea 에 채우기만" do
      # 자동 저장 신호 (예: requestSubmit 호출) 가 음성 인식 결과 후엔 없어야 함.
      # toggleVoice / _startVoice / _stopVoice 안에 form.requestSubmit() 없음 확인.
      voice_section = js[/_initVoiceRecognition.*?\n  _showError/m]
      expect(voice_section).not_to include("requestSubmit"),
        "음성 인식 결과가 자동 저장되면 ADR-013 위반"
    end

    it "에러 핸들러 — 마이크 권한·네트워크 실패 시 안내" do
      expect(js).to include('addEventListener("error"')
      expect(js).to include("마이크 권한")
    end

    it "녹음 중 토글 색상 변화 — voice-btn--active" do
      expect(js).to include("quick-modal__voice-btn--active")
    end

    it "모달 close 시 녹음 자동 정지 (리소스 누수 방지)" do
      close_method = js[/  close\(\) \{.*?\n  \}/m]
      expect(close_method).to include("_stopVoice")
    end
  end

  describe "CSS — voice-pulse 애니메이션" do
    let(:css) { File.read(File.join(Sowing.root, "public/css/application.css")) }

    it "녹음 중 빨강 + pulse 애니메이션" do
      expect(css).to include(".quick-modal__voice-btn--active")
      expect(css).to include("voice-pulse")
      expect(css).to include("rgb(220, 38, 38)")
    end
  end
end
