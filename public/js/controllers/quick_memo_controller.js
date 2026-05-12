import { Controller } from "@hotwired/stimulus"

// 빠른 메모 모달 컨트롤러.
// - 글로벌 단축키: Cmd/Ctrl + Shift + M → 모달 열기
// - 텍스트영역에서 Cmd/Ctrl + Enter → 폼 제출
// - Turbo 제출 성공 시: 모달 닫고 textarea 비우기
// - 실패 시: 모달 유지, 서버가 반환한 #quick_modal_error 메시지 표시
//
// 2026-05-12 — 4축 분류 chip (ADR-016):
//   ⚡ 일반 / 👤 인물 / 📚 교과 / 📄 문서 / 🪞 정체성
//   chip 선택 시 hidden subject input 갱신 → POST /memos 가 subject ENUM 저장.
//   서버가 body 에 #4축명 태그 자동 부착 (lib/sowing/controllers/memos_controller.rb).

// 4축 ENUM (ADR-016). "" 는 분류 없음 (일반).
// Stimulus 가 static 필드를 특수 처리할 수 있어 모듈 상수로 분리 (안전한 패턴).
const VALID_SUBJECTS = ["", "person", "subject", "document", "identity"]

// 옛 subtype 명 → 새 4축 매핑 (북마크 호환: /write/book 등이 보낸 ?write=).
const LEGACY_SUBTYPE_MAP = {
  general: "",
  book: "document",
  lecture: "subject",
  emotion: "identity",
  student: "person"
}

export default class extends Controller {
  static targets = ["dialog", "textarea", "form", "error", "chip", "subjectInput",
                    "voice", "voiceBtn", "voiceLabel"]

  connect() {
    this._onGlobalKeydown = this._onGlobalKeydown.bind(this)
    document.addEventListener("keydown", this._onGlobalKeydown)

    this._initVoiceRecognition()

    // /write/{type} 진입 시 ?write= query param 으로 모달 자동 열기 + chip prefill
    const params = new URLSearchParams(window.location.search)
    const writeType = params.get("write")
    if (writeType) {
      const subject = LEGACY_SUBTYPE_MAP[writeType] ?? writeType
      if (VALID_SUBJECTS.includes(subject)) {
        requestAnimationFrame(() => {
          this._activateSubject(subject)
          this.open()
        })
      }
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this._onGlobalKeydown)
    this._stopVoice()
  }

  // ─── 음성 입력 (Web Speech API) ──────────────────────────────────────
  _initVoiceRecognition() {
    const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!Recognition) return

    if (this.hasVoiceTarget) this.voiceTarget.hidden = false

    this._recognition = new Recognition()
    this._recognition.lang = "ko-KR"
    this._recognition.interimResults = true
    this._recognition.continuous = true
    this._recognition.maxAlternatives = 1

    this._voiceActive = false
    this._voiceBaseValue = ""

    this._recognition.addEventListener("result", (event) => {
      let interim = ""
      let final = ""
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const transcript = event.results[i][0].transcript
        if (event.results[i].isFinal) {
          final += transcript
        } else {
          interim += transcript
        }
      }
      const combined = (this._voiceBaseValue + (final ? final : interim)).trim()
      this.textareaTarget.value = combined
      if (final) {
        this._voiceBaseValue = (this._voiceBaseValue + final).trim() + " "
      }
    })

    this._recognition.addEventListener("error", (event) => {
      this._showError(`음성 인식 오류: ${event.error} — 마이크 권한·인터넷 연결 확인`)
      this._setVoiceState(false)
    })

    this._recognition.addEventListener("end", () => this._setVoiceState(false))
  }

  toggleVoice() {
    if (!this._recognition) return
    this._voiceActive ? this._stopVoice() : this._startVoice()
  }

  _startVoice() {
    try {
      this._voiceBaseValue = this.textareaTarget.value
      if (this._voiceBaseValue && !this._voiceBaseValue.endsWith(" ")) {
        this._voiceBaseValue += " "
      }
      this._recognition.start()
      this._setVoiceState(true)
    } catch (e) {
      this._showError("음성 입력 시작 실패: " + e.message)
    }
  }

  _stopVoice() {
    if (this._recognition && this._voiceActive) {
      try { this._recognition.stop() } catch (e) { /* ignore */ }
    }
    this._setVoiceState(false)
  }

  _setVoiceState(active) {
    this._voiceActive = active
    if (!this.hasVoiceBtnTarget) return
    this.voiceBtnTarget.classList.toggle("quick-modal__voice-btn--active", active)
    if (this.hasVoiceLabelTarget) {
      this.voiceLabelTarget.textContent = active ? "녹음 중… 다시 누르면 정지" : "음성 입력"
    }
    this.voiceBtnTarget.setAttribute("aria-label",
      active ? "음성 입력 정지" : "음성 입력 시작")
  }

  _showError(msg) {
    if (this.hasErrorTarget) this.errorTarget.textContent = msg
  }

  _onGlobalKeydown(event) {
    const key = (window.SOWING_SHORTCUTS?.quick_memo || "m").toLowerCase()
    if ((event.metaKey || event.ctrlKey) && event.shiftKey && event.key.toLowerCase() === key) {
      event.preventDefault()
      this.open()
    }
  }

  open() {
    if (this.hasDialogTarget && !this.dialogTarget.open) {
      this.dialogTarget.showModal()
      this._clearError()
      requestAnimationFrame(() => this.textareaTarget.focus())
    }
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) {
      this._stopVoice()
      this.dialogTarget.close()
    }
  }

  // 4축 chip 클릭 — hidden subject input 갱신 + 활성 표시.
  selectSubject(event) {
    const subject = event.currentTarget.dataset.subject ?? ""
    this._activateSubject(subject)
  }

  _activateSubject(subject) {
    if (!VALID_SUBJECTS.includes(subject)) return

    this.chipTargets.forEach(chip => {
      const isActive = (chip.dataset.subject ?? "") === subject
      chip.classList.toggle("quick-modal__chip--active", isActive)
      chip.setAttribute("aria-checked", isActive ? "true" : "false")
    })

    if (this.hasSubjectInputTarget) {
      this.subjectInputTarget.value = subject
    }
  }

  // Cmd/Ctrl + Enter → 폼 제출
  onTextareaKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  // Turbo 응답 처리 직후
  onSubmitEnd(event) {
    if (event.detail.success) {
      this.textareaTarget.value = ""
      this._clearError()
      this._activateSubject("") // 일반으로 reset
      this.close()
    }
  }

  _clearError() {
    if (this.hasErrorTarget) this.errorTarget.textContent = ""
  }
}
