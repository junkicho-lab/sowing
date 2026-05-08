import { Controller } from "@hotwired/stimulus"

// 빠른 메모 모달 컨트롤러.
// - 글로벌 단축키: Cmd/Ctrl + Shift + M → 모달 열기
// - 텍스트영역에서 Cmd/Ctrl + Enter → 폼 제출
// - Turbo 제출 성공 시: 모달 닫고 textarea 비우기
// - 실패 시: 모달 유지, 서버가 반환한 #quick_modal_error 메시지 표시
export default class extends Controller {
  static targets = ["dialog", "textarea", "form", "error"]

  connect() {
    this._onGlobalKeydown = this._onGlobalKeydown.bind(this)
    document.addEventListener("keydown", this._onGlobalKeydown)
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
      requestAnimationFrame(() => this.textareaTarget.focus())
    }
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) {
      this.dialogTarget.close()
    }
  }

  // Cmd/Ctrl + Enter → 폼 제출
  onTextareaKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  // Turbo가 응답을 처리한 직후
  onSubmitEnd(event) {
    if (event.detail.success) {
      this.textareaTarget.value = ""
      this._clearError()
      this.close()
    }
    // 실패 시: 서버 turbo-stream이 #quick_modal_error를 채움 — 모달 유지
  }

  _clearError() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ""
    }
  }
}
