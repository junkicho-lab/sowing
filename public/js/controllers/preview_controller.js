import { Controller } from "@hotwired/stimulus"

// 마크다운 라이브 프리뷰.
// editor 컨트롤러가 dispatch 하는 'editor:input' (bubbling) 이벤트 수신 → 디바운스 → POST /preview.
// Turbo Stream 응답이 #preview_pane을 update.
//
// values:
//   url        — POST 엔드포인트 (기본 "/preview")
//   debounceMs — 입력 후 대기 시간 (기본 300ms, ROADMAP W2-T07)
export default class extends Controller {
  static values = {
    url: { type: String, default: "/preview" },
    debounceMs: { type: Number, default: 300 }
  }

  connect() {
    this._timeout = null
    this._textarea = this.element.querySelector("[data-editor-target='textarea']")
    if (!this._textarea) return

    this._onInput = () => this.schedule()
    this.element.addEventListener("editor:input", this._onInput)
  }

  disconnect() {
    if (this._timeout) clearTimeout(this._timeout)
    if (this._onInput) this.element.removeEventListener("editor:input", this._onInput)
  }

  schedule() {
    if (this._timeout) clearTimeout(this._timeout)
    this._timeout = setTimeout(() => this.render(), this.debounceMsValue)
  }

  async render() {
    if (!this._textarea) return

    const formData = new FormData()
    formData.append("body", this._textarea.value)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { Accept: "text/vnd.turbo-stream.html" },
        body: formData
      })
      if (!response.ok) return
      const streamHtml = await response.text()
      // Turbo가 글로벌로 등록한 헬퍼로 stream을 적용 — DOM의 #preview_pane을 update.
      window.Turbo?.renderStreamMessage(streamHtml)
    } catch (e) {
      // 네트워크 오류는 silent (다음 입력 시 재시도)
      // eslint-disable-next-line no-console
      console.error("[preview] render failed", e)
    }
  }
}
