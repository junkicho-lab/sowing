import { Controller } from "@hotwired/stimulus"

// 통합 빠른 검색 모달 (W4-T04).
// - 글로벌 단축키: Cmd/Ctrl+K → modal showModal + input focus
// - 입력 시 200ms 디바운스 → /api/quick_search?q=…
// - 결과: ↑↓로 이동, Enter로 navigate, Esc로 닫음 (<dialog> 자동)
//
// values:
//   url        — fetch endpoint (기본 "/api/quick_search")
//   debounceMs — 입력 후 API 호출 지연 (기본 200ms)
export default class extends Controller {
  static targets = ["dialog", "input", "results"]
  static values = {
    url: { type: String, default: "/api/quick_search" },
    debounceMs: { type: Number, default: 200 }
  }

  connect() {
    this._timeout = null
    this._selectedIndex = -1
    this._items = []

    this._onGlobalKeydown = this._onGlobalKeydown.bind(this)
    document.addEventListener("keydown", this._onGlobalKeydown)
  }

  disconnect() {
    if (this._timeout) clearTimeout(this._timeout)
    document.removeEventListener("keydown", this._onGlobalKeydown)
  }

  _onGlobalKeydown(event) {
    // Cmd/Ctrl + K → 열기
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.open()
    }
  }

  open() {
    if (this.hasDialogTarget && !this.dialogTarget.open) {
      this.dialogTarget.showModal()
      this.inputTarget.value = ""
      this._clearResults()
      requestAnimationFrame(() => this.inputTarget.focus())
    }
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) {
      this.dialogTarget.close()
    }
  }

  // <input>의 input 이벤트 — 디바운스 후 fetch.
  onInput() {
    if (this._timeout) clearTimeout(this._timeout)
    this._timeout = setTimeout(() => this.search(), this.debounceMsValue)
  }

  // <input>의 keydown 이벤트 — ↑↓ 선택 이동, Enter navigate.
  onKey(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this._moveSelection(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this._moveSelection(-1)
    } else if (event.key === "Enter") {
      event.preventDefault()
      this._navigateSelected()
    }
  }

  async search() {
    const q = this.inputTarget.value.trim()
    if (q.length === 0) {
      this._clearResults()
      return
    }

    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) return
      const data = await response.json()
      this._renderResults(data.results || [])
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error("[quick-search] fetch failed", e)
    }
  }

  _renderResults(items) {
    this._items = items
    this._selectedIndex = items.length > 0 ? 0 : -1

    if (items.length === 0) {
      this.resultsTarget.innerHTML = '<li class="quick-search__empty">결과가 없습니다.</li>'
      return
    }

    this.resultsTarget.innerHTML = items.map((item, idx) => `
      <li class="quick-search__item ${idx === 0 ? "quick-search__item--selected" : ""}" data-quick-search-index="${idx}">
        <a href="${item.url}" class="quick-search__link">
          <span class="quick-search__icon">${item.icon || "·"}</span>
          <span class="quick-search__title">${this._escape(item.title)}</span>
          <span class="quick-search__mode">${item.mode}</span>
        </a>
      </li>
    `).join("")
  }

  _clearResults() {
    this._items = []
    this._selectedIndex = -1
    this.resultsTarget.innerHTML = ""
  }

  _moveSelection(delta) {
    if (this._items.length === 0) return
    const len = this._items.length
    this._selectedIndex = (this._selectedIndex + delta + len) % len
    const lis = this.resultsTarget.querySelectorAll(".quick-search__item")
    lis.forEach((li, i) => {
      li.classList.toggle("quick-search__item--selected", i === this._selectedIndex)
    })
    lis[this._selectedIndex]?.scrollIntoView({ block: "nearest" })
  }

  _navigateSelected() {
    const item = this._items[this._selectedIndex]
    if (!item) return
    window.location.href = item.url
  }

  _escape(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
