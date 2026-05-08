import { Controller } from "@hotwired/stimulus"
import { EditorView, basicSetup } from "codemirror"
import { markdown } from "@codemirror/lang-markdown"
import { autocompletion } from "@codemirror/autocomplete"

// 본문 #태그 자동완성 source (W3-T05).
// "#" 직후 letter/digit/_/-/`/` 매칭. 이미 사용된 distinct 태그 목록 반환.
async function hashtagSource(context) {
  const before = context.matchBefore(/(?<![\p{L}\p{N}_])#([\p{L}\p{N}_/-]*)$/u)
  if (!before) return null

  const query = before.text.slice(1) // "#xxx" → "xxx"

  try {
    const response = await fetch(
      `/api/tag_complete?q=${encodeURIComponent(query)}`,
      { headers: { Accept: "application/json" } }
    )
    if (!response.ok) return null
    const data = await response.json()

    return {
      from: before.from + 1, // # 다음부터
      options: (data.tags || []).map((t) => ({
        label: t,
        type: "tag",
        apply: t
      })),
      validFor: /^[\p{L}\p{N}_/-]*$/u
    }
  } catch {
    return null
  }
}

// 위키링크 자동완성 source (W3-T04).
// [[ 입력 시 cursor 직전 패턴을 매칭, /api/wiki_complete?q=… 호출.
// validFor: cursor 뒤 ] · | · \n이 들어오면 query 무효화 → 새 source 호출.
async function wikiLinkSource(context) {
  const before = context.matchBefore(/\[\[([^\]|\n]*)$/)
  if (!before) return null

  const query = before.text.slice(2) // "[[xxx" → "xxx"

  try {
    const response = await fetch(
      `/api/wiki_complete?q=${encodeURIComponent(query)}`,
      { headers: { Accept: "application/json" } }
    )
    if (!response.ok) return null
    const data = await response.json()

    return {
      from: before.from + 2, // [[ 다음부터 query 시작
      options: data.results.map((r) => ({
        label: r.title,
        type: r.mode,        // record/note/memo — CodeMirror가 자동으로 색 구분
        detail: r.icon,      // 우측 보조 텍스트 (📖/📝/💭)
        apply: `${r.title}]]`
      })),
      validFor: /^[^\]|\n]*$/
    }
  } catch {
    return null
  }
}

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
        // [[ 입력 시 200ms 후 자동완성 팝업 — 위키링크 source만 노출 (override).
        // [[ 또는 # 입력 시 200ms 후 자동완성. 패턴 다르므로 두 source 공존 가능.
        autocompletion({
          override: [wikiLinkSource, hashtagSource],
          activateOnTypingDelay: 200
        }),
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
