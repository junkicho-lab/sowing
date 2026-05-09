# Sowing 평가 — Karpathy의 Software 3.0 관점에서

작성: 2026-05-09
대상 독자: Sowing 메인테이너, 향후 기여자, agentic engineering 도입을 검토하는 운영자

본 문서는 [`background.md`](background.md) 의 12가지 명제를 기준으로 Sowing v0.1.0
(8주 MVP) 이 무엇을 잘했고 무엇을 놓쳤는지 솔직하게 평가하고, 후속 개선 방향을
구체적으로 제안합니다. 추상적 원칙이 아니라 **무엇을 추가/제거/재구성할지**까지
적습니다.

---

## 0. 한 줄 요약

> Sowing은 **agent-native 데이터 레이어** (마크다운 SoT, 결정적 도메인, 검증 가능한
> 인덱스) 를 우연히 잘 갖춘 반면, **agent-facing 표면** (MCP 서버·LLM 합성·구조화
> 로그) 은 거의 비어 있다.
>
> Phase 1 (W1~W8) 은 Software 1.0 으로 성공했다. Phase 2 의 과제는
> **Software 3.0 으로 진화하되, 검증 가능성을 잃지 않는 것**이다.

---

## 1. 12가지 명제별 Sowing 채점

각 명제마다 ✅ (잘 맞음) / 🟡 (부분적) / ❌ (미흡) 로 표기.

### 1.1 December 2025 Was an Agentic Inflection Point

> "프로그래머는 코드 작성자가 아니라 에이전트 오케스트레이터로 변하고 있다."

**점수: ✅** (개발 측면)

- Sowing 자체가 8주간 사람-Claude Code 협업으로 만들어졌다. 855건 spec, 13개
  컨트롤러, 2026-05-01~05-09 중 일관된 페이스. 이것이 곧 agentic engineering의
  실증.
- ROADMAP 기반 단계별 검증, lint/test 의무화, 5x stress 통과, doctor 자동 진단 —
  Karpathy가 말한 "fallible agents 조정 + 품질 보존" 의 구현 사례.

**의미**: 본 코드베이스 자체가 "agentic engineering으로 진짜 앱이 만들어진다"의
존재 증명 (existence proof). 후속 기여자는 이를 학습 자료로 쓸 수 있다.

### 1.2 Software 3.0 — Context Window as the New Program

> "Software 1.0 (코드) → 2.0 (데이터셋·신경망) → 3.0 (LLM·컨텍스트·도구)."

**점수: ❌**

Sowing은 **순수 Software 1.0**. 모든 기능이 결정적 Ruby 코드:
- 검색: FTS5 + LIKE (LLM 0)
- 자동완성: prefix matching (LLM 0)
- 입양 (AdoptOrphan): path-based 규칙 추론 (LLM 0)
- 충돌 해결: 사용자 직접 Keep Mine/Theirs (LLM 0)

이건 **나쁜 것이 아니다**. v0.1.0 의 명확한 동작·예측성·오프라인성 모두 1.0의
직접 산물. 그러나 Software 3.0이 가능한 곳에 그것을 검토조차 안 한 것은 회피.

**핵심 관찰**: Karpathy의 MenuGen 논리를 적용하면 일부 기능은 *사라질 수 있다*.
§2 에서 다시 다룸.

### 1.3 MenuGen 모먼트 — 사라지는 앱

> "AI는 옛날 앱을 빠르게 만드는 게 아니다. 어떤 앱은 존재를 멈춰야 한다."

**점수: ❌** (자기 검토 부재)

Sowing의 어느 부분이 사라질 수 있는가? 정직하게 따져보면:

| 현재 기능 | Software 3.0 대안 | 판단 |
|----------|-------------------|------|
| `/templates` UI + 12종 템플릿 | "LLM에 '오늘 수업 회고 작성해줘' 라고 말함" | 🟡 부분 사라질 가능 |
| `/search` 모드/카테고리/태그/날짜 필터 폼 | 자연어 질의 ("4월에 협동학습 관련 메모") | 🟡 폼은 남되 자연어 입력 옵션 추가 |
| 위키링크 자동완성 (200ms 디바운스 + prefix) | LLM이 본문 의미를 보고 후보 제시 | 🟡 보강 가능 |
| `/tags` 클라우드 | LLM이 의미 기반 클러스터링 | ❌ 그대로 유지 (확정적이라 좋음) |
| 메모→필기 승격 폼 | "이 메모를 필기로 정리해줘" | 🟡 LLM 보조 옵션 추가 |
| 통계·streak 카드 | LLM이 자연어 요약 ("이번 주 빠진 날: 화·목, 가장 활발했던 날: 월요일 7건") | 🟡 카드는 유지하되 옆에 통찰 한 줄 |

**결론**: Sowing은 "어떤 앱은 사라져야 한다"는 자문(自問)을 안 했다. Phase 2의
첫 작업은 **각 화면마다 'LLM이 직접 변환해주면 이 화면은 필요한가?'** 를 묻는 것.

### 1.4 새 기회 = 더 빠른 프로그래밍이 아니다

> "이전엔 불가능했는데 이제 자연스러운 정보 변환이 무엇인가?"

**점수: ❌** (가장 큰 기회 미실현)

이전엔 불가능했고 이제 가능한 것 중, **Sowing의 도메인 (한국 교사) 에 직접 적용
가능**한 것:

1. **학기말 회고 자동 합성**
   - 입력: 한 학기 분량의 메모·필기·기록
   - 출력: "이 학기에 자주 등장한 학생 5명, 가장 자주 다룬 주제 3개, 변화의
     순간들" — 사람이 절대 손으로 못 합치는 합성

2. **학생별 누적 페이지 자동 생성**
   - 입력: 메모·기록에 등장한 학생 이름들
   - 출력: 학생당 1페이지에 모든 언급·관찰·변화·만남 히스토리
   - 이게 곧 Karpathy의 LLM Wiki 패턴

3. **수업 패턴 추출**
   - 입력: 수업 회고 기록 누적
   - 출력: "잘 된 수업의 공통점, 아쉬운 수업의 공통점" — 분석

4. **모순 탐지**
   - 입력: 학생 관찰 메모들
   - 출력: "민준이는 4월엔 '소극적'으로 5월엔 '적극적'으로 묘사 — 변화 시점은
     5월 5일 협동학습 도입 후"

5. **빠진 공백 알림**
   - 입력: 학급 명단 + 누적 기록
   - 출력: "지난 4주간 한 번도 등장 안 한 학생: 7명" (방치 방지)

이 다섯 가지는 모두 "기존 코드로 견고히 못 만드는 것" 인데 LLM으로는 가능.
Sowing의 실질 가치를 한 단계 끌어올리는 자물쇠.

### 1.5 검증 가능성 (Verifiability) 이 빠른 자동화의 이유

> "전통 SW는 명세 가능한 것을, LLM/RL은 검증 가능한 것을 자동화한다."

**점수: ✅** (인프라 측면에서 매우 강함)

Sowing은 검증 가능성을 잘 세팅했다:
- 855건 RSpec spec — 회귀 자동 검증
- standardrb lint clean — 스타일 자동 검증
- ConsistencyCheck — 데이터 정합성 자동 검증 (인덱스 wipe → 자동 재구축)
- 도메인은 결정적 — 같은 입력에 같은 출력 (Memo·Note·Record 직렬화 round-trip)
- doctor의 9개 섹션 — 운영 환경 자동 검증

이건 LLM 기능 추가 시 **결정적 큰 무기**다. 어떤 LLM 보조 기능이든 다음을 만족
하면 안전하게 도입 가능:
- 결과를 마크다운 파일로 저장 (롤백 가능)
- 사용자가 검토·편집 가능 (자동 적용 안 함)
- 기존 spec이 깨지지 않음 (격리)

**실천 함의**: LLM 기능은 "별도 use case + spec + 사람 검토" 패턴으로만 추가.
chat-style overlay 금지.

### 1.6 Jagged Intelligence — 검증 가능성 × 학습 관심

> "모델은 verifiable + lab의 학습 우선 영역에서 능력 폭발, 그 외엔 이상함."

**점수: 🟡** (영향 인지는 됐으나 활용 미흡)

Sowing 도메인에 대해:
- **한국어 ✓**: 프론티어 모델 모두 한국어 잘함
- **마크다운 ✓**: 학습 데이터에 풍부
- **교사 한국어 일지 ⚠**: 영어보다 데이터 부족 → 결과 품질 변동 가능
- **위키링크 의미 추론 ⚠**: 옵시디언 사용자 데이터가 학습에 들어간 정도 불확실

**함의**: Sowing의 LLM 기능은 "rails" 안에 있다고 가정하고 시작 가능. 하지만
한국어 교사 글쓰기 스타일 (높임말 혼용, 줄임 표현) 은 별도 평가셋(eval) 만들어
검증 권장.

**actionable**: Phase 2 시작 시 한국어 교사 글 100건짜리 eval 데이터셋부터 구축.

### 1.7 Vibe Coding vs. Agentic Engineering

> "Vibe coding은 floor를, agentic engineering은 ceiling을 올린다."

**점수: ✅** (이미 후자로 만들어짐)

Sowing은 vibe-built 가 아니다:
- 매 작업마다 spec 먼저 (TDD·BDD)
- ROADMAP 단위 분해 (W1~W8 마일스톤)
- lint·test·5x stress 게이트
- ADR (DECISIONS.md) 로 의사결정 보존

이건 이미 Karpathy가 권장한 방식. **자랑할 만하다**.

**함의**: Sowing 사용자 (교사) 에게도 동일 원리를 적용할 여지 있음.
- "vibe writing" — 떠오른 한 줄 메모 (기존 빠른 메모, ✅ 이미 있음)
- "agentic writing" — 메모를 LLM과 함께 깊은 기록으로 정련 (✅ 미실현, 큰 기회)

### 1.8 Hiring Should Change — 큰 프로젝트 + 적대적 에이전트 검증

> "코딩 퍼즐이 아니라, 큰 프로젝트 만들고 보안·견고성 검증."

**점수: N/A** (Sowing은 채용 도구 아님)

직접 적용 안 됨. 다만 **간접 함의**: Sowing 자체가 "agentic engineering 으로 만든
큰 프로젝트" 의 사례 — 신규 기여자 평가나 자기 학습용 자료로 가치 있음.

### 1.9 Founders: Valuable Verifiable Environments — 미개척 검증 환경 찾기

> "프론티어 랩이 아직 안 다룬, 가치 있고 검증 가능한 영역에서 RL 환경 만들기."

**점수: 🟡** (잠재력 큼, 미실현)

한국 교사 일지·회고는 정확히 그런 영역:
- **가치 있음**: 한국 K-12 교사 ~50만, 매일 발생, 학습 효과 있음
- **검증 가능 (부분)**: 일관성, 시간순, 인물·주제 연결, 사실 일치성 등 검증 가능한
  지표 다수
- **프론티어 학습 미커버**: 한국어 교사 일지 코퍼스가 큰 모델 학습에 비중 있게
  들어갔을 가능성 낮음

**Sowing이 RL 환경이 될 수 있는 길**:
- 사용자가 LLM 제안을 수락/거절 → preference data
- 모순 탐지 정답률 → 검증 보상
- 학생 관찰 합성 품질을 사용자가 ⭐ 평가 → reward signal

이걸 모으면 Sowing 자체가 한국 교사 도메인의 미세조정 데이터 광맥이 된다.
**프라이버시 우선 (로컬)** 정책이라 데이터 수집은 옵트인이어야 하지만 — 동의한
사용자 한정 fine-tuning corpus는 가치 막대함.

### 1.10 Agent-Native Infrastructure — Sensors and Actuators

> "Agent를 위해 만들어라. 마크다운 docs, CLI, API, MCP 서버, 구조화 로그."

**점수: 🟡** (절반 됨)

| 항목 | Sowing 상태 |
|------|------------|
| 마크다운 docs | ✅ 모든 데이터가 마크다운 (SoT) |
| CLI | 🟡 `bin/sowing memo`, `bin/sowing-doctor`, rake 태스크 — 부분 |
| API (HTTP) | 🟡 3개 엔드포인트만 (`/api/wiki_complete`, `/api/tag_complete`, `/api/quick_search`) |
| MCP 서버 | ❌ 없음 |
| 구조화 로그 | ❌ 없음 (Sinatra 기본 로그만) |
| 머신 가독 스키마 | 🟡 ADR-004 응답 형식, frontmatter 스펙 — 있으나 OpenAPI 같은 형식적 정의 없음 |
| 복붙 가능한 agent 지시문 | ❌ 없음 (README 사람용 위주) |
| 안전한 권한 모델 | 🟡 로컬 단일 사용자라 minimal — agent 위임 시 미흡 |
| 감사 가능한 액션 | 🟡 휴지통은 있으나 변경 로그 없음 |
| Headless 셋업 | 🟡 `rake db:setup` + `SOWING_VAULT` env — OK |

**가장 큰 공백: MCP 서버**. Sowing의 sensors (검색·통계·entry 조회) 와 actuators
(메모 작성·승격·태그 부여) 를 MCP 도구로 노출하면 사용자의 Claude/Codex/
ChatGPT 에이전트가 Sowing 을 직접 쓸 수 있다.

**구체 예시 (Phase 2 후보)**:
```
mcp__sowing__list_memos(since: "2026-05-01")
mcp__sowing__create_memo(body: "...")
mcp__sowing__search(q: "협동학습", mode: "note")
mcp__sowing__promote_memo(id: "01...", to: "note", category: "lessons", source: "...")
mcp__sowing__stats_summary(date_range: "2026-05")
```

이게 있으면 ChatGPT 모바일에서 "오늘 1교시 학생 발표 자원함" 이라 말하면 자동
메모 저장. iPhone 17 문제도 자연 해결 (앱 별도 안 만들어도 ChatGPT가 Sowing의
sensor·actuator 사용).

### 1.11 Ghosts, Not Animals

> "LLM은 동물이 아닌 통계적 시뮬레이션. 의인화하면 오판한다."

**점수: ✅** (의인화 0)

Sowing은 LLM을 안 쓰니까 의인화 자체가 없음. **그러나** Phase 2에서 LLM 도입할
때 이 원칙이 중요:

- 챗봇 UI 금지 (Sowing은 도구이지 대화 상대 아님)
- "AI가 추천합니다" 같은 anthropomorphic 카피 자제
- 에러 시 "AI가 헷갈렸어요" 가 아니라 "모델 출력이 검증 통과 못 했습니다" 로

**원칙**: LLM 결과는 항상 **사용자가 검토 가능한 마크다운 패치 형태**로 제시.
"동물이 의견을 말하는" 게 아니라 "도구가 변환을 제안하는" 인터페이스.

### 1.12 Education — 사고는 위임해도 이해는 위임 못 한다

> "에이전트가 일을 더 해도, 인간은 무엇이 가치 있는지 이해해야 한다."

**점수: 🟡** (목표는 일치, 수단 미흡)

Sowing의 **존재 이유**가 곧 이 명제와 같음:
- "옵시디언을 배우려고 앱을 켜는 게 아니라, 앱을 매일 쓰다 보면 옵시디언을 쓰고
  있게 된다"
- 즉 **도구 학습이 아니라 실천 자체가 목적**. 이해를 외주화 안 함.

**그러나 현재 Sowing은 "기록 도구" 까지만 도와주고, "기록을 통한 이해 향상"은
사용자에게 맡긴다**. Karpathy의 LLM Wiki 비전을 적용하면 한 단계 더 갈 수 있다:

- 사용자가 글을 씀 (이해 단계 1: 기록)
- LLM이 합성·요약·연결을 제안 (이해 단계 2: 통찰 후보)
- 사용자가 수락·수정·거절 (이해 단계 3: 자기 해석으로 흡수)

이게 진짜 "이해 향상 도구". 통계 카드는 데이터 표시이지 통찰이 아니다.

---

## 2. 무엇을 빼고 무엇을 더할 것인가 — MenuGen 렌즈

Karpathy: "어떤 앱은 존재를 멈춰야 한다."

### 2.1 그대로 유지 (결정적 가치 큼)

- ✅ 마크다운 SoT — 옵시디언 호환·로컬 우선의 핵심
- ✅ 메모/필기/기록 도메인 — 인지 모델로서의 가치 명확
- ✅ ULID 식별자, frontmatter 스펙 — 검증 가능한 기반
- ✅ Sync (FileWatcher + 충돌 처리) — 양방향 편집의 인프라
- ✅ doctor·spec·lint — 검증 가능성의 인프라
- ✅ 휴지통 (`.sowing/trash`), 충돌 백업 (`.sowing/conflicts`) — 데이터 손실 방지

### 2.2 단순화 또는 LLM 위임 검토

| 기능 | 현재 | 검토 방향 |
|------|------|-----------|
| 12종 교사 템플릿 UI | 정적 마크다운 + `{{key}}` | 유지하되 "LLM에 즉석 생성" 옵션 추가 — `/templates/generate?prompt=...` |
| 검색 폼 (모드·카테고리·태그·날짜) | 결정적 SQL 필터 | 유지하되 자연어 입력 박스 병행 — LLM이 필터 추론 |
| 통계 카드 (오늘/주/월) | 정적 카운트 | 유지하되 옆에 한 줄 통찰 추가 — "이번 주 가장 풍성한 날: 월요일 (협동학습 도입)" |
| 위키링크 자동완성 (prefix) | LIKE 매칭 | 유지하되 의미 기반 후보 보강 — "민준 이라는 학생을 언급했으니 [[학생 관찰: 민준]] 도 후보" |
| 인터랙티브 튜토리얼 | 4단계 정적 | 사용자 작성 메모 분석해 다음 단계 동적 안내 |

**원칙**: 결정적 동작은 *기본값*, LLM은 *옵션 보강*. 둘 다 같은 화면에 공존.

### 2.3 새로 추가 (이전엔 불가능, 이제 자연스러움)

§1.4 의 다섯 가지를 Phase 2~4 로 분배:

**Phase 2 (P1, 4주)**
- MCP 서버 — sensors·actuators 노출 (§1.10)
- 한국어 교사 글 eval 셋 100건 (§1.6)

**Phase 3 (P2, 4주)**
- 학생별 누적 페이지 자동 생성 (LLM Wiki 패턴 1)
- 빠진 공백 알림 (방치 방지)

**Phase 4 (P3, 4주)**
- 학기말 회고 자동 합성
- 수업 패턴 추출
- 모순 탐지

각 기능은 다음 4개 산출물 1세트로:
1. Use Case (Dry::Monads Result, 결정적 인터페이스)
2. spec (입력·기대 출력·실패 케이스)
3. eval (한국어 교사 글에 대한 품질 측정)
4. UI (제안 → 사용자 검토 → 수락/수정/거절)

### 2.4 진짜로 사라질 수 있는 것

솔직히 말해:
- **자체 검색 UI** 의 일부는 사라질 수 있다. ChatGPT 등 외부 에이전트가 MCP로
  접근하면 사용자는 "Sowing에 협동학습 5월 메모" 라고 말하기만 하면 됨. 검색
  화면 방문 자체가 줄어듦.
- **태그 클라우드** — LLM이 의미 기반 클러스터를 동적으로 만들 수 있으면 정적
  클라우드 가치는 줄어듦.
- **수동 승격 폼** — "이 메모를 필기로" LLM 한 번이면 충분. 폼은 결과 검토용.

이건 **나쁜 일이 아니다**. 사용자 시간을 더 높은 층위 (이해·해석) 로 옮기는
것. Sowing 의 정체성은 UI 구성 요소가 아니라 마크다운 SoT + 도메인 모델.

---

## 3. 개선 로드맵 — Phase 9~16 (Phase 1 = W1~W8)

### Phase 9 (4주): Agent-Native Surface

**목표**: Sowing 의 sensors·actuators 를 외부 에이전트가 쓸 수 있게.

| 주 | 작업 |
|----|------|
| 1 | MCP 서버 (mcp gem 또는 Ruby 직접 구현) — Stdio transport |
| 2 | 도구 노출: list_memos, search, create_memo, promote, stats_summary |
| 3 | 구조화 로그 (JSON lines, `.sowing/audit.log`) — 모든 mutation |
| 4 | OpenAPI 스펙 + agent 지침 (`docs/AGENT_GUIDE.md`) — 복붙 가능한 instructions |

**검증**: Claude Desktop / ChatGPT / Codex 에서 MCP 연결 → 5종 명령 성공.

### Phase 10 (4주): Eval Infrastructure

**목표**: LLM 기능 도입 전에 검증 환경 먼저.

| 주 | 작업 |
|----|------|
| 1 | 한국어 교사 글 eval 코퍼스 100건 (옵트인 사용자 기여) |
| 2 | 합성 품질 평가 메트릭 (사실 일치성·간결성·관련성) |
| 3 | LLM-judge harness (모델 출력 → 자동 채점) |
| 4 | CI 통합 — 모델 변경 시 회귀 자동 측정 |

**검증**: 임의 LLM 출력 1건 입력 → eval 점수 자동 산출.

### Phase 11 (4주): Tier-1 LLM 합성 — 학생 페이지 + 공백 알림

**목표**: 가장 즉각 가치 있는 합성 2개.

| 주 | 작업 |
|----|------|
| 1 | EntityExtractor Use Case — entries에서 학생/주제/장소 추출, IndexRepo entities 테이블 |
| 2 | StudentDigest 생성기 — 학생당 1 마크다운 (vault/.sowing/synth/students/) |
| 3 | GapDetector — 4주 미언급 학생 알림 (대시보드 카드) |
| 4 | UI — synthesized pages 별도 영역 ("이건 LLM 생성입니다" 명시) + 사용자 수락/거절 |

**검증**: eval 코퍼스에서 학생 디제스트 정확률 ≥ 80%.

### Phase 12 (4주): Tier-2 LLM 합성 — 회고·패턴·모순

| 주 | 작업 |
|----|------|
| 1 | 학기말 회고 합성 (입력: 100~500건 entries) |
| 2 | 수업 패턴 추출 (잘된 vs 아쉬웠던 수업 공통점) |
| 3 | 모순 탐지 (시간 순 변화·논리 비일관성) |
| 4 | 통합 UI — `/synth` 라우트 |

### Phase 13~16 (예약, Phase 11~12 결과에 따라)

- iOS 동반 앱 (SwiftUI, read-mostly, MCP 클라이언트) — 만약 Phase 9 MCP 서버가
  잘 작동하면 가치 명확해짐
- 다크 모드, 단축키 사용자 정의
- 다국어 (i18n 인프라 활용)
- 모바일 웹 UX 개선
- Tebako 패키징 본격 검증 + OS별 인스톨러 (W8 deferred 작업)

---

## 4. 측정 가능한 성공 지표 (verifiability 원칙)

각 Phase의 마일스톤은 자동 측정 가능해야 한다.

| Phase | 지표 | 임계값 |
|-------|------|--------|
| 9 | MCP 서버 — 외부 에이전트의 도구 호출 성공률 | ≥ 95% |
| 9 | 새 spec 추가 (MCP 라우팅·권한·로그) | +30 spec |
| 10 | eval 코퍼스 크기 | ≥ 100 sample |
| 10 | LLM-judge 신뢰도 (사람-judge 일치) | ≥ 0.8 카파 |
| 11 | 학생 디제스트 사실 일치성 | ≥ 80% |
| 11 | 사용자 수락률 (제안 → 수락) | ≥ 50% |
| 12 | 회고 합성 길이 | 500~2000자 (너무 짧거나 길면 fail) |
| 전체 | 회귀 — 기존 855 spec 통과 | 100% (1.0 깨지면 release block) |

---

## 5. 무엇을 안 할 것인가 — 명시적 거부

Karpathy가 강조한 "ghosts not animals" 와 "understanding not thinking" 을 따라
**다음은 의도적으로 거부한다**:

1. ❌ **챗봇 UI** — Sowing 안에 ChatGPT 클론 절대 안 만듦. 외부 에이전트 (Claude
   Desktop, ChatGPT) 가 MCP 로 Sowing에 접근하는 게 정답.
2. ❌ **자동 글쓰기** — LLM이 사용자 대신 메모/필기/기록 작성 안 함. 합성·요약·
   연결만. **글은 교사 본인이 쓴다** (이해 외주화 거부).
3. ❌ **클라우드 LLM 강제** — 모든 LLM 기능은 옵션. 옵트인. 로컬 LLM (Ollama 등)
   백엔드도 동등 지원.
4. ❌ **"AI가 ~ 생각합니다"** 같은 카피 — 도구지 동물 아님 (§1.11).
5. ❌ **Agent가 자율로 vault 변경** — 모든 mutation은 사용자 명시 수락 필요.
   Audit log 의무.

---

## 6. 결론

Karpathy의 12 명제로 점검한 결과:

- ✅ Sowing 은 검증 가능성·결정적 도메인·agentic engineering 으로 만들어진 점에서
  Software 3.0 시대의 **좋은 하부 인프라** 다.
- ❌ Sowing 은 정작 LLM 통합·agent-facing surface·합성 기능이 0 이라 Software 1.0
  시대의 모범생에 머문다.
- 🎯 진짜 가치는 **Phase 9~12 의 agent-native 표면 + LLM 합성** 에서 나온다.
  Phase 1 (8주) 은 그 기반을 만든 것이고, 진정한 의미의 Sowing 은 아직 시작도
  안 했다.

다행히 **이미 깐 인프라 위에 LLM 기능을 안전히 얹을 수 있는 구조** 가 있다:
- 마크다운 SoT — LLM 출력도 마크다운 patch 로 표현 가능
- spec·doctor·ConsistencyCheck — LLM 기능 도입 시 회귀 자동 검증
- Use Case 패턴 (Dry::Monads Result) — LLM 호출도 같은 인터페이스로 감쌈
- 휴지통·충돌 백업 — LLM 결과 적용 후에도 롤백 가능

**다음 행동 권고**: Phase 9 (MCP 서버) 부터. 일주일에 하나의 sensor/actuator 추가.
4주 후 외부 에이전트가 Sowing 을 쓸 수 있게 됨 → 자연스럽게 §2.3 의 새 가능성이
열림.

---

## 부록 A: Sowing 강점 vs Karpathy 권장 매트릭스 요약

| 명제 | Sowing 점수 | 핵심 근거 |
|------|------------|----------|
| §1.1 Agentic 변곡점 | ✅ | 본 코드베이스가 agentic engineering 산물 |
| §1.2 Software 3.0 | ❌ | 100% 결정적 코드, LLM 0 |
| §1.3 MenuGen — 사라질 앱 | ❌ | 자기 검토 안 함 |
| §1.4 새 기회 | ❌ | LLM Wiki 패턴 미실현 |
| §1.5 검증 가능성 | ✅ | 855 spec, doctor, ConsistencyCheck |
| §1.6 Jagged | 🟡 | 한국어는 OK, 한국어 교사 도메인 eval 부재 |
| §1.7 Vibe vs Agentic | ✅ | spec-first 로 만들어짐 |
| §1.9 검증 환경 | 🟡 | 한국 교사 도메인은 미개척 광맥, 미활용 |
| §1.10 Agent-native | 🟡 | SoT·CLI·일부 API 있으나 MCP 부재 |
| §1.11 Ghosts not animals | ✅ | 의인화 0 (LLM 안 쓰니까) |
| §1.12 Education | 🟡 | 목표 일치, 합성 도구 부재 |

**총평**: 데이터·인프라 부분은 4/5, agent-facing·LLM 합성은 0/5.
Phase 9~12 가 이 격차를 메울 길.

---

## 부록 B: 본 평가의 한계

- 이 평가는 **2026-05-09 시점 코드 + ROADMAP** 만 봤다. 실제 사용자 피드백 0.
  베타 테스터 작업 (W8-T07 deferred) 후 재평가 권장.
- "LLM 기능이 정말 가치 있는가?" 는 미검증 가설. Phase 10 의 eval 코퍼스 + 사용자
  수락률로 검증해야 함. 가설이 틀리면 Phase 11~12 보류.
- Karpathy 의 12 명제는 시장·기술 환경에 종속. 6개월 후 재독 시 일부 명제는 약해질
  수 있음. 본 문서는 라이브 문서로 갱신 필요.

---

> *"You can outsource your thinking, but you can't outsource your understanding."*
> — Andrej Karpathy, Sequoia Ascent 2026
>
> Sowing 의 다음 4개월 (Phase 9~12) 은 이 한 줄에 헌정된다. 교사들이 더 빨리
> 쓰게 하는 것이 아니라, 더 깊이 이해하게 만드는 것.
