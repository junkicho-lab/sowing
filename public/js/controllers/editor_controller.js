import { Controller } from "@hotwired/stimulus"
import { EditorView, basicSetup } from "codemirror"
import { markdown } from "@codemirror/lang-markdown"

// CodeMirror 6 마크다운 에디터.
// textarea를 숨기고 CodeMirror 뷰로 교체. 입력은 실시간으로 textarea에 동기화하여
// 폼 제출 시 자연스럽게 서버로 전송 (JS 비활성 시는 plain textarea 그대로 동작 — progressive enhancement).
export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    const initial = this.textareaTarget.value

    // display:none + required는 브라우저별 검증 동작이 불일치 → required 제거.
    // 서버측 validation(empty_body Failure → 422 + 폼 에코)이 fallback이라 UX 문제 없음.
    this.textareaTarget.removeAttribute("required")
    this.textareaTarget.style.display = "none"

    this.host = document.createElement("div")
    this.host.className = "cm-host"
    this.textareaTarget.before(this.host)

    this.view = new EditorView({
      doc: initial,
      extensions: [
        basicSetup,
        markdown(),
        EditorView.lineWrapping,
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            this.textareaTarget.value = update.state.doc.toString()
            // 외부 컨트롤러(예: preview)가 입력 변경을 구독할 수 있도록 bubbling 이벤트 발행.
            this.textareaTarget.dispatchEvent(new CustomEvent("editor:input", { bubbles: true }))
          }
        })
      ],
      parent: this.host
    })
  }

  disconnect() {
    if (this.view) {
      this.view.destroy()
      this.host?.remove()
      this.textareaTarget.style.display = ""
    }
  }
}
