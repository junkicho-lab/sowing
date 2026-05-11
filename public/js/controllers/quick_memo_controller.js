import { Controller } from "@hotwired/stimulus"

// 빠른 메모 모달 컨트롤러.
// - 글로벌 단축키: Cmd/Ctrl + Shift + M → 모달 열기
// - 텍스트영역에서 Cmd/Ctrl + Enter → 폼 제출
// - Turbo 제출 성공 시: 모달 닫고 textarea 비우기
// - 실패 시: 모달 유지, 서버가 반환한 #quick_modal_error 메시지 표시
//
// Phase 13 W26-T01 — 5 subtype chip (일반·책·강의·감정·학생):
// - chip 선택 시 해당 subtype 의 slot field 표시
// - submit 직전 body 자동 결합 (slot 값 + textarea 내용 + 자동 태그)
// - 서버는 그대로 POST /memos body= 수신 — 도메인 변경 0
export default class extends Controller {
  static targets = ["dialog", "textarea", "form", "error", "chip", "slots"]

  connect() {
    this._onGlobalKeydown = this._onGlobalKeydown.bind(this)
    document.addEventListener("keydown", this._onGlobalKeydown)
    this._currentSubtype = "general"

    // /write/{type} 진입 시 query param 으로 모달 자동 열기 + subtype prefill
    const params = new URLSearchParams(window.location.search)
    const writeType = params.get("write")
    if (writeType && this._isValidSubtype(writeType)) {
      // 다음 tick — DOM 안정화 후
      requestAnimationFrame(() => {
        this._activateSubtype(writeType)
        this.open()
      })
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this._onGlobalKeydown)
  }

  _onGlobalKeydown(event) {
    // Cmd/Ctrl + Shift + M → 열기
    if ((event.metaKey || event.ctrlKey) && event.shiftKey && event.key.toLowerCase() === "m") {
      event.preventDefault()
      this.open()
    }
  }

  open() {
    if (this.hasDialogTarget && !this.dialogTarget.open) {
      this.dialogTarget.showModal()
      this._clearError()
      // 다음 tick에 focus (Safari에서 showModal 직후 focus가 무시되는 경우 회피)
      requestAnimationFrame(() => {
        // 활성 slot 의 첫 input 이 있으면 그쪽, 없으면 textarea
        const activeSlot = this._activeSlotElement()
        const firstInput = activeSlot?.querySelector('input:not([type="hidden"])')
        if (firstInput) {
          firstInput.focus()
        } else {
          this.textareaTarget.focus()
        }
      })
    }
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) {
      this.dialogTarget.close()
    }
  }

  // Subtype chip 클릭 — UI 활성화 + slot 표시
  selectSubtype(event) {
    const subtype = event.currentTarget.dataset.subtype
    this._activateSubtype(subtype)
  }

  _activateSubtype(subtype) {
    if (!this._isValidSubtype(subtype)) return
    this._currentSubtype = subtype

    // chip 활성화 표시
    this.chipTargets.forEach(chip => {
      const isActive = chip.dataset.subtype === subtype
      chip.classList.toggle("quick-modal__chip--active", isActive)
      chip.setAttribute("aria-checked", isActive ? "true" : "false")
    })

    // slot 표시 분기
    this.slotsTarget.querySelectorAll("[data-subtype-slot]").forEach(slot => {
      slot.hidden = slot.dataset.subtypeSlot !== subtype
    })

    // 활성 slot 의 첫 input 으로 focus
    requestAnimationFrame(() => {
      const activeSlot = this._activeSlotElement()
      const firstInput = activeSlot?.querySelector('input:not([type="hidden"])')
      firstInput?.focus()
    })
  }

  _isValidSubtype(subtype) {
    return ["general", "book", "lecture", "emotion", "student"].includes(subtype)
  }

  _activeSlotElement() {
    if (this._currentSubtype === "general") return null
    return this.slotsTarget.querySelector(`[data-subtype-slot="${this._currentSubtype}"]`)
  }

  // 감정 chip 한 개만 선택
  selectEmotion(event) {
    const chip = event.currentTarget
    const emotion = chip.dataset.emotion
    const hiddenInput = this.slotsTarget.querySelector('[data-slot-key="emotion"]')

    // 같은 chip 다시 누르면 선택 해제
    if (chip.classList.contains("quick-modal__emotion-chip--active")) {
      chip.classList.remove("quick-modal__emotion-chip--active")
      hiddenInput.value = ""
      return
    }

    // 다른 chip 모두 비활성화
    this.slotsTarget.querySelectorAll(".quick-modal__emotion-chip").forEach(c => {
      c.classList.remove("quick-modal__emotion-chip--active")
    })
    chip.classList.add("quick-modal__emotion-chip--active")
    hiddenInput.value = emotion
  }

  // Cmd/Ctrl + Enter → 폼 제출
  onTextareaKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  // 폼 제출 직전 — body 결합 (slot + textarea + 자동 태그)
  onSubmit(event) {
    const subtype = this._currentSubtype
    if (subtype === "general") return // 일반은 그대로

    const slots = this._readSlots(subtype)
    const userBody = this.textareaTarget.value.trim()
    const combined = this._assembleBody(subtype, slots, userBody)
    this.textareaTarget.value = combined
  }

  _readSlots(subtype) {
    const slotEl = this._activeSlotElement()
    if (!slotEl) return {}
    const out = {}
    slotEl.querySelectorAll("[data-slot-key]").forEach(input => {
      out[input.dataset.slotKey] = (input.value || "").trim()
    })
    return out
  }

  _assembleBody(subtype, slots, userBody) {
    const lines = []
    let tags = []

    switch (subtype) {
      case "book": {
        if (slots.book_title) lines.push(`**📖 책:** ${slots.book_title}`)
        if (slots.book_page) lines.push(`**페이지:** ${slots.book_page}`)
        tags.push("#책기록")
        break
      }
      case "lecture": {
        if (slots.lecture_speaker) lines.push(`**🎤 강사:** ${slots.lecture_speaker}`)
        if (slots.lecture_topic) lines.push(`**주제:** ${slots.lecture_topic}`)
        tags.push("#강의기록")
        break
      }
      case "emotion": {
        if (slots.emotion) lines.push(`**💭 감정:** ${slots.emotion}`)
        tags.push("#감정")
        break
      }
      case "student": {
        if (slots.student_name) {
          lines.push(`**👤 학생:** ${slots.student_name}`)
          // 학생 이름도 태그로 — 학급 명단 매칭 시 자동 entity 인덱싱
          tags.push(`#${slots.student_name}`)
        }
        tags.push("#학생관찰")
        break
      }
    }

    // 결합 — slot lines (있으면) + 빈 줄 + 사용자 본문 + 빈 줄 + 태그
    const parts = []
    if (lines.length > 0) parts.push(lines.join("\n"))
    if (userBody) parts.push(userBody)
    if (tags.length > 0) parts.push(tags.join(" "))
    return parts.join("\n\n")
  }

  // Turbo가 응답을 처리한 직후
  onSubmitEnd(event) {
    if (event.detail.success) {
      this.textareaTarget.value = ""
      this._clearError()
      this._resetSlots()
      this._activateSubtype("general")
      this.close()
    }
    // 실패 시: 서버 turbo-stream이 #quick_modal_error를 채움 — 모달 유지
  }

  _resetSlots() {
    if (!this.hasSlotsTarget) return
    this.slotsTarget.querySelectorAll('input').forEach(input => {
      if (input.type === "hidden") {
        input.value = ""
      } else {
        input.value = ""
      }
    })
    this.slotsTarget.querySelectorAll(".quick-modal__emotion-chip--active").forEach(c => {
      c.classList.remove("quick-modal__emotion-chip--active")
    })
  }

  _clearError() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ""
    }
  }
}
