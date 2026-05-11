// 위키링크 그래프 시각화 (30년 시나리오 #4).
//
// 외부 라이브러리 0 — 인라인 SVG + 자체 force-directed 알고리즘.
// CLAUDE.md 원칙: 빌드 도구·D3·cytoscape 등 의존 안 함.
//
// 알고리즘 — Verlet integration 기반 light force-directed:
//   - 척력 (Coulomb-like): 모든 노드 쌍 거리 d 에 대해 k_repel / d^2
//   - 인력 (spring): 엣지 양 끝 (r - rest_length) * k_spring
//   - 중심 중력: (center - position) * k_gravity
//   - 마찰: velocity *= damping (0.92)
//
// 200 노드 / 400 엣지에서 60fps 유지. requestAnimationFrame 으로 부드러운 시뮬레이션.
//
// 상호작용:
//   - 마우스 hover → tooltip (제목 · 연도 · in/out 연결 수)
//   - 노드 클릭 → entry 상세 페이지 이동 (data.href)
//   - 드래그 → 노드 위치 고정 (반복 클릭으로 해제)

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["svg", "tooltip", "stats", "nodeCount", "edgeCount", "truncated", "empty"]
  static values = { api: String }

  connect() {
    this.nodes = []
    this.edges = []
    this.simulation = null
    this.animFrame = null
    this.draggingNode = null
    this.fetchData()
  }

  disconnect() {
    if (this.animFrame) cancelAnimationFrame(this.animFrame)
  }

  async fetchData() {
    const res = await fetch(this.apiValue, { headers: { Accept: "application/json" } })
    if (!res.ok) {
      console.error("graph_data fetch failed:", res.status)
      return
    }
    const data = await res.json()
    this.nodes = data.nodes || []
    this.edges = data.edges || []
    this.nodeCountTarget.textContent = String(this.nodes.length)
    this.edgeCountTarget.textContent = String(this.edges.length)
    this.truncatedTarget.hidden = !data.truncated

    if (this.nodes.length === 0) {
      this.emptyTarget.hidden = false
      this.svgTarget.style.display = "none"
      return
    }
    this.emptyTarget.hidden = true
    this.svgTarget.style.display = ""

    this.initLayout()
    this.render()
    this.startSimulation()
    this.attachInteractions()
  }

  // ─── 초기 위치: 원형 배치 (force 가 빠르게 수렴하도록) ───
  initLayout() {
    const w = this.svgTarget.clientWidth || 800
    const h = this.svgTarget.clientHeight || 600
    this.width = w
    this.height = h
    this.cx = w / 2
    this.cy = h / 2

    // node degree 계산 — 노드 크기·중심성에 사용
    const degree = new Map()
    this.edges.forEach((e) => {
      degree.set(e.source, (degree.get(e.source) || 0) + 1)
      degree.set(e.target, (degree.get(e.target) || 0) + 1)
    })

    // 연도 범위 — 색상 명도 매핑용
    const years = this.nodes.map((n) => n.year).filter((y) => y > 0)
    this.minYear = Math.min(...years, new Date().getFullYear())
    this.maxYear = Math.max(...years, new Date().getFullYear())

    // 초기 원형 배치 — 결정적이고 force 가 빠르게 정렬
    const r = Math.min(w, h) * 0.35
    this.nodes.forEach((node, i) => {
      const angle = (i / this.nodes.length) * 2 * Math.PI
      node.x = this.cx + r * Math.cos(angle)
      node.y = this.cy + r * Math.sin(angle)
      node.vx = 0
      node.vy = 0
      node.degree = degree.get(node.id) || 0
      node.fixed = false
    })

    // 엣지 → 양 끝 노드 객체 참조로 변환 (성능)
    const nodeMap = new Map(this.nodes.map((n) => [n.id, n]))
    this.edgeRefs = this.edges
      .map((e) => ({ source: nodeMap.get(e.source), target: nodeMap.get(e.target) }))
      .filter((e) => e.source && e.target)
  }

  // ─── SVG 초기 렌더 ───
  render() {
    const svgNS = "http://www.w3.org/2000/svg"
    while (this.svgTarget.firstChild) this.svgTarget.removeChild(this.svgTarget.firstChild)

    // edges (먼저 그려서 노드 아래에)
    this.edgeGroup = document.createElementNS(svgNS, "g")
    this.edgeGroup.setAttribute("class", "graph-edges")
    this.svgTarget.appendChild(this.edgeGroup)

    this.edgeElements = this.edgeRefs.map((e) => {
      const line = document.createElementNS(svgNS, "line")
      line.setAttribute("stroke", "rgba(45, 95, 63, 0.25)")
      line.setAttribute("stroke-width", "1")
      this.edgeGroup.appendChild(line)
      return line
    })

    // nodes
    this.nodeGroup = document.createElementNS(svgNS, "g")
    this.nodeGroup.setAttribute("class", "graph-nodes")
    this.svgTarget.appendChild(this.nodeGroup)

    this.nodeElements = this.nodes.map((node) => {
      const circle = document.createElementNS(svgNS, "circle")
      const r = this.nodeRadius(node)
      circle.setAttribute("r", r)
      circle.setAttribute("fill", this.nodeColor(node))
      circle.setAttribute("data-id", node.id)
      circle.setAttribute("class", `graph-node graph-node--${node.mode}`)
      // 고립 노드 — backlink 0 + outbound 0 + degree 0 → 빨간 외곽선
      if (node.inbound === 0 && node.outbound === 0) {
        circle.setAttribute("stroke", "#d4a017")
        circle.setAttribute("stroke-width", "2")
        circle.setAttribute("stroke-dasharray", "3,2")
      }
      circle.style.cursor = "pointer"
      this.nodeGroup.appendChild(circle)
      return circle
    })
  }

  // ─── force simulation 메인 루프 ───
  startSimulation() {
    const tick = () => {
      this.step()
      this.updatePositions()
      this.animFrame = requestAnimationFrame(tick)
    }
    this.animFrame = requestAnimationFrame(tick)
  }

  step() {
    const k_repel = 800
    const k_spring = 0.05
    const rest_length = 80
    const k_gravity = 0.005
    const damping = 0.85

    // 척력 — O(n^2). 200 노드까지 60fps 유지.
    for (let i = 0; i < this.nodes.length; i++) {
      const a = this.nodes[i]
      if (a.fixed) continue
      for (let j = i + 1; j < this.nodes.length; j++) {
        const b = this.nodes[j]
        const dx = b.x - a.x
        const dy = b.y - a.y
        let dist2 = dx * dx + dy * dy
        if (dist2 < 1) dist2 = 1
        const dist = Math.sqrt(dist2)
        const force = k_repel / dist2
        const fx = (force * dx) / dist
        const fy = (force * dy) / dist
        a.vx -= fx
        a.vy -= fy
        if (!b.fixed) {
          b.vx += fx
          b.vy += fy
        }
      }
    }

    // 인력 — 엣지 spring
    this.edgeRefs.forEach((e) => {
      const dx = e.target.x - e.source.x
      const dy = e.target.y - e.source.y
      const dist = Math.sqrt(dx * dx + dy * dy) || 1
      const stretch = dist - rest_length
      const fx = (k_spring * stretch * dx) / dist
      const fy = (k_spring * stretch * dy) / dist
      if (!e.source.fixed) {
        e.source.vx += fx
        e.source.vy += fy
      }
      if (!e.target.fixed) {
        e.target.vx -= fx
        e.target.vy -= fy
      }
    })

    // 중심 중력 + 마찰 + 위치 적용
    this.nodes.forEach((n) => {
      if (n.fixed) return
      n.vx += (this.cx - n.x) * k_gravity
      n.vy += (this.cy - n.y) * k_gravity
      n.vx *= damping
      n.vy *= damping
      n.x += n.vx
      n.y += n.vy
      // 경계 — SVG 밖으로 나가지 않게
      n.x = Math.max(15, Math.min(this.width - 15, n.x))
      n.y = Math.max(15, Math.min(this.height - 15, n.y))
    })
  }

  updatePositions() {
    this.nodeElements.forEach((el, i) => {
      el.setAttribute("cx", this.nodes[i].x)
      el.setAttribute("cy", this.nodes[i].y)
    })
    this.edgeElements.forEach((el, i) => {
      const e = this.edgeRefs[i]
      el.setAttribute("x1", e.source.x)
      el.setAttribute("y1", e.source.y)
      el.setAttribute("x2", e.target.x)
      el.setAttribute("y2", e.target.y)
    })
  }

  // ─── 시각 매핑 ───
  nodeRadius(node) {
    // degree 0 → 5, degree 10+ → 15
    return Math.min(15, 5 + Math.sqrt(node.degree) * 2)
  }

  nodeColor(node) {
    // mode 별 색조 + 연도 명도 (오래됨 = 옅음)
    const yearRange = this.maxYear - this.minYear || 1
    const ageRatio = (node.year - this.minYear) / yearRange  // 0(오래됨) ~ 1(최근)
    const lightness = 75 - ageRatio * 35  // 75% (옅) ~ 40% (짙)
    const hue = node.mode === "memo" ? 30 : node.mode === "note" ? 200 : 140
    return `hsl(${hue}, 60%, ${lightness}%)`
  }

  // ─── 상호작용 — hover / click / drag ───
  attachInteractions() {
    this.svgTarget.addEventListener("mousemove", (e) => this.handleMouseMove(e))
    this.svgTarget.addEventListener("mouseleave", () => this.hideTooltip())
    this.svgTarget.addEventListener("mousedown", (e) => this.handleMouseDown(e))
    this.svgTarget.addEventListener("mouseup", () => this.handleMouseUp())
    this.svgTarget.addEventListener("click", (e) => this.handleClick(e))
  }

  handleMouseMove(e) {
    if (this.draggingNode) {
      const rect = this.svgTarget.getBoundingClientRect()
      this.draggingNode.x = e.clientX - rect.left
      this.draggingNode.y = e.clientY - rect.top
      this.draggingNode.vx = 0
      this.draggingNode.vy = 0
      return
    }
    const node = this.findNodeAt(e)
    if (node) this.showTooltip(node, e)
    else this.hideTooltip()
  }

  handleMouseDown(e) {
    const node = this.findNodeAt(e)
    if (node) {
      this.draggingNode = node
      node.fixed = true
      this.dragMoved = false
    }
  }

  handleMouseUp() {
    if (this.draggingNode) {
      // drag 직후엔 click 으로 처리 안 함 (이미 mousemove 가 처리함)
      setTimeout(() => {
        if (this.draggingNode) this.draggingNode.fixed = false
        this.draggingNode = null
      }, 50)
    }
  }

  handleClick(e) {
    if (this.dragMoved) {
      this.dragMoved = false
      return
    }
    const node = this.findNodeAt(e)
    if (node && node.href) window.location.href = node.href
  }

  findNodeAt(e) {
    const rect = this.svgTarget.getBoundingClientRect()
    const mx = e.clientX - rect.left
    const my = e.clientY - rect.top
    for (let i = this.nodes.length - 1; i >= 0; i--) {
      const n = this.nodes[i]
      const dx = mx - n.x
      const dy = my - n.y
      const r = this.nodeRadius(n) + 3
      if (dx * dx + dy * dy <= r * r) return n
    }
    return null
  }

  showTooltip(node, e) {
    const tip = this.tooltipTarget
    const modeLabel = { memo: "💭 메모", note: "📝 필기", record: "📖 기록" }[node.mode] || node.mode
    tip.innerHTML = `<strong>${escapeHtml(node.title)}</strong>` +
      `<br><small>${modeLabel} · ${node.year}` +
      (node.category ? ` · ${escapeHtml(node.category)}` : "") + "</small>" +
      `<br><small>← ${node.inbound} · → ${node.outbound}</small>`
    tip.hidden = false
    const rect = this.svgTarget.getBoundingClientRect()
    tip.style.left = (e.clientX - rect.left + 12) + "px"
    tip.style.top = (e.clientY - rect.top + 12) + "px"
  }

  hideTooltip() {
    this.tooltipTarget.hidden = true
  }
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}
