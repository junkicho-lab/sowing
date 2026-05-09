# Sowing Agent Guide — MCP 사용 안내

> 본 문서는 Claude Desktop / Codex / Continue.dev / Zed 등 MCP 클라이언트에서
> Sowing 의 sensor·actuator 를 사용하는 방법을 안내합니다.
> Phase 9 (Agent-Native Surface) 산출물.

---

## 빠른 시작 (5분)

### 1. Sowing 코드베이스 준비

```sh
cd /path/to/sowing
bundle install
bundle exec rake db:setup    # 최초 1회
bin/sowing-doctor            # 9개 섹션 모두 정상인지 확인
```

`bin/sowing-mcp` 가 실행 가능한지 확인:

```sh
chmod +x bin/sowing-mcp
ls -l bin/sowing-mcp         # 실행 권한 있어야 함
```

### 2. Claude Desktop 등록

`~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) 또는
`%APPDATA%\Claude\claude_desktop_config.json` (Windows) 에 다음 추가:

```json
{
  "mcpServers": {
    "sowing": {
      "command": "/Users/woodncarpenter/projects/sowing/bin/sowing-mcp"
    }
  }
}
```

> 경로는 본인 환경의 절대 경로로 교체. `~` 확장 안 됨.

Claude Desktop 재시작 → 우측 하단 🔌 아이콘에 sowing 나타남.

### 3. 첫 도구 호출

Claude 채팅에 입력:
> "Sowing 의 시스템 상태를 알려줘"

Claude 가 `health` 도구를 호출해 다음과 같은 응답:
```
Sowing v0.1.0 (development)
- 볼트: ~/Documents/SowingVault
- 메모 12 / 필기 4 / 기록 4 (총 20)
- 충돌 백업 0건, audit log 활성
```

성공이면 5분 내 셋업 완료.

---

## 도구 카탈로그 (12개)

### 🔍 Sensors (read-only, 4개)

#### `list_memos` — 모드별 entry 목록 페이징

```
mode: "memo" | "note" | "record"  (기본 "memo")
limit: 1~100  (기본 30)
offset: 0+   (기본 0)
```

**예시 응답**:
```json
{
  "mode": "memo",
  "count": 30,
  "entries": [
    {
      "id": "01KR1SAMP00000000000000004",
      "mode": "memo",
      "path": "00_Inbox/2026-05-07_170000.md",
      "title": null,
      "created_at": "2026-05-07T17:00:00+09:00",
      "tags": ["회고", "협동학습"]
    }
  ]
}
```

본문은 미포함 — 본문 필요 시 `read_entry` 호출.

#### `search` — 한국어 본문·제목 검색

```
q: 검색어 (필수, 비어 있으면 에러)
mode?: "memo" | "note" | "record"
category?: 카테고리 정확 일치
tag?: 태그 (case-insensitive)
limit: 1~50  (기본 20)
```

한국어 자동 라우팅 (3+자 FTS5, 2자는 LIKE 폴백).

#### `read_entry` — 단일 entry 본문

```
id?: ULID (예: 01KR1SAMP...)
path?: vault 기준 상대 경로
```
둘 중 하나 필수.

응답에 frontmatter 모든 필드 + body 전체 포함.

#### `health` — 시스템 상태

매개변수 없음. 다음 반환:
- 버전 / env / vault_dir
- 모드별 entry 카운트
- audit_log 존재 여부 + 줄 수

---

### ✏️ Actuators (write, 4개)

> 모든 actuator 는 audit log 에 `actor: "agent"` 로 자동 기록됩니다.
> `vault/.sowing/audit.log` 에서 직접 확인 가능.

#### `create_memo` — 빠른 메모 생성

```
body: 메모 본문 (필수)
tags?: ["수업", "협동학습"]
```

#### `create_note` — 필기 생성

```
title:    필수
body:     필수
category: "lessons" | "trainings" | "books" | "meetings"  (필수)
source:   필수 (책 제목·연수 이름 등)
tags?
```

저장 위치: `20_Notes/{category}/{slug}.md`

#### `create_record` — 기록 생성

```
title:    필수
body:     필수
category: 자유 텍스트 (예: "학급운영", "회고", "평가")
tags?
```

저장 위치: `30_Records/{YYYY}/{category}/{slug}.md`

#### `promote` — 메모/필기 승격

```
id:       승격 대상 ULID (필수)
to:       "note" | "record"  (필수)
title:    승격 후 제목 (필수)
category: 카테고리 (필수)
source?:  to=note 면 필수
tags?:    nil 이면 원본 entry tags 유지
```

ID 유지 (백링크·위키링크 그래프 보존). 옛 path 는 휴지통(`.sowing/trash`)으로.

---

### 📊 Analytics (read-only, 4개)

#### `stats_summary` — 통계 + 성장 단계

매개변수 없음.

```json
{
  "today": {"date": "2026-05-09", "total": 3, "memos": 2, "notes": 1, "records": 0},
  "this_week": 12,
  "this_month": 45,
  "streak_days": 7,
  "total_all_time": 178,
  "growth": {
    "stage": "tree",
    "label": "🌳 나무",
    "message": "한 그루의 나무가 되었습니다. 이제 그늘을 만들어요.",
    "next_threshold": 150,
    "remaining_to_next": null,
    "progress_ratio": 1.0
  }
}
```

#### `tag_cloud` — 태그 빈도

```
limit?: 1~200 (기본 50)
```

#### `wiki_complete` — 위키링크 후보

```
q?:     title substring (빈 문자열 허용)
limit?: 1~100 (기본 25)
```

note/record title 에서 매칭. 메모는 title 없어 제외.

#### `recent` — 모드 통합 최근순

```
limit?: 1~50 (기본 10)
```

`list_memos` 와 달리 모든 모드 통합.

---

## 자주 쓰는 프롬프트 5종

복붙해서 그대로 사용 가능.

### 1. 이번 주 활동 요약

> "Sowing 의 이번 주 통계와 가장 최근 메모 5건을 알려줘. 어떤 패턴이 보이는지도 한 줄로 짚어줘."

내부 호출: `stats_summary` + `recent(limit: 5)`. Claude 가 자연어로 합성.

### 2. 학생 검색 + 본문 인용

> "민준 학생이 등장한 entries 를 찾고, 가장 인상적인 한 줄을 인용해서 정리해줘."

내부: `search(q: "민준")` → 결과별 `read_entry(id:)` → 본문에서 발췌.

### 3. 메모 → 필기 승격 보조

> "방금 작성한 메모 [01KR...] 를 협동학습 카테고리 필기로 정리해줘. 제목은 너가 좋다고 생각하는 것으로."

내부: `read_entry(id:)` → 사용자 검토 → `promote(to: "note", category: "lessons", source: "...")`. Claude 가 source 와 title 제안, 사용자가 승인.

### 4. 자주 쓰는 태그로 검색

> "내가 자주 쓰는 태그 상위 5개와, 그 중 첫 번째 태그가 붙은 entries 10건을 보여줘."

내부: `tag_cloud(limit: 5)` → `search(tag: "수업")`.

### 5. 모바일에서 즉석 메모

> "오늘 1교시 학생 발표 자원함" — Claude 가 알아서 메모로 저장해줘.

내부: `create_memo(body: "오늘 1교시 학생 발표 자원함", tags: ["수업"])`.

iPhone/iPad 의 ChatGPT/Claude 모바일 앱에서도 동일 — MCP 게이트웨이 만들면 별도 iOS 앱 불필요.

---

## 안전한 사용 패턴

### 1. Mutation 검토 습관

LLM 이 잘못된 도구 인자 추론 가능. 다음 mutation 은 **사용자 명시 수락 후** 실행:

- `create_memo` 이상의 도구 (note·record·promote)
- 의외의 카테고리·source 값
- title 이 너무 일반적인 경우 (예: "회고")

Claude 가 도구 호출 전 의도를 한 줄로 확인하면 안전:
> "다음 필기를 만들려고 합니다: 카테고리=lessons, 출처='학기 초 수업', 제목='협동학습 첫 시도'. 진행할까요?"

### 2. Audit log 확인

언제든 누가 어떤 mutation 했는지 검증 가능:

```sh
tail -20 ~/Documents/SowingVault/.sowing/audit.log | jq -c '{actor, action, mode, entry_id}'
```

`actor: "agent"` 줄이 곧 MCP 호출. `"user"` 는 웹 UI / CLI 직접 호출. `"filesystem"` 은 외부 에디터 동기화.

### 3. 휴지통 신뢰

CLAUDE.md 5번 원칙: 영구 삭제 금지. 모든 삭제는 `.sowing/trash/` 로 이동.
잘못 만든 entry 는 웹 UI 에서 promote → 다른 모드로 변환하거나, 직접 trash 에서 복구.

### 4. 거부 항목 (ADR-013 Phase 2 명시적 거부)

다음은 본 MCP 서버가 **절대 하지 않습니다**:

- ❌ LLM 이 사용자 대신 글 작성 — 합성·요약·연결만. 본문은 사용자가 직접
- ❌ 자율 mutation — 모든 변경은 사용자가 LLM 응답 검토 후 명시 호출
- ❌ 의인화 카피 — Sowing 은 도구이지 동물이 아닙니다 (Karpathy ghosts-not-animals)

---

## 다른 MCP 클라이언트 설정

### Codex (Anthropic)

`~/.config/codex/mcp_servers.json`:

```json
{
  "sowing": {
    "command": "/Users/woodncarpenter/projects/sowing/bin/sowing-mcp"
  }
}
```

### Continue.dev

`~/.continue/config.json` 의 `experimental.modelContextProtocolServers`:

```json
{
  "transport": {
    "type": "stdio",
    "command": "/Users/woodncarpenter/projects/sowing/bin/sowing-mcp"
  }
}
```

### Zed

`~/.config/zed/settings.json`:

```json
{
  "context_servers": {
    "sowing": {
      "command": "/Users/woodncarpenter/projects/sowing/bin/sowing-mcp",
      "args": []
    }
  }
}
```

### 직접 stdio 테스트 (개발용)

```sh
(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}'
 echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
 sleep 0.5) | bin/sowing-mcp | jq .
```

---

## Troubleshooting

### "도구 호출 실패" / 빈 응답

- `bin/sowing-doctor` 실행 → 9개 섹션 점검
- `bundle exec rspec spec/mcp/` — MCP 도구 spec 통과 확인
- audit log 가 비어 있어 `stats_summary` 가 0 만 반환하면 정상 (vault 비어 있음)

### "MCP 서버를 찾을 수 없음"

- 절대 경로 확인 — `~` 확장 안 됨
- 실행 권한: `chmod +x bin/sowing-mcp`
- Claude Desktop 완전 종료 (Cmd+Q) 후 재실행 — 단순 윈도우 닫기 부족

### `SOWING_VAULT` 환경 변수 적용

MCP 클라이언트가 spawn 한 프로세스는 **부모 프로세스의 env 를 상속**. 다른 vault 사용:

Claude Desktop config:
```json
{
  "mcpServers": {
    "sowing": {
      "command": "/path/to/bin/sowing-mcp",
      "env": {
        "SOWING_VAULT": "/Users/me/Dropbox/MyVault"
      }
    }
  }
}
```

### 도구 결과가 너무 길어 짤림

- `limit` 파라미터 명시 (기본값 활용 안 함)
- `read_entry` 는 본문 전체 반환 — 매우 긴 기록은 짤릴 수 있음. Claude 에 "본문은 첫 500자만" 같은 후처리 지시.

### 한글 file path / title 깨짐

`bin/sowing-doctor` 의 `[환경]` 섹션에서 `Encoding: external=UTF-8` 확인.
아니면 `LANG=ko_KR.UTF-8` 설정 후 재시작.

---

## 도구 입출력 spec 검증

LLM 출력이 의심스러우면 spec 으로 결정적 동작 확인:

```sh
bundle exec rspec spec/mcp/   # 60+ MCP 도구 spec
```

또는 audit log 직접 검사:

```sh
jq -s 'group_by(.actor) | map({actor: .[0].actor, count: length})' \
  ~/Documents/SowingVault/.sowing/audit.log
```

`actor=agent` 카운트가 예상보다 많으면 LLM 이 의도 외 mutation 한 것일 수 있음 — 검토.

---

## 다음 단계 (Phase 10+)

본 가이드의 도구들은 모두 **결정적**입니다. LLM 추론은 외부 클라이언트(Claude/Codex)
가 담당. Phase 10 부터는 Sowing 자체에 LLM-합성 기능이 추가될 예정:

- `synthesize_student_digest` (Phase 11) — 학생별 누적 페이지 생성
- `synthesize_semester_reflection` (Phase 12) — 학기말 회고 합성
- `detect_contradictions` (Phase 12) — 시간 흐름·인물 묘사 모순 탐지

이들은 본 MCP 서버에 추가될 예정 — Phase 10 의 eval 인프라 검증 후.

---

## 참조

- [ROADMAP.md](../ROADMAP.md) Phase 2 (W9~W24)
- [docs/DECISIONS.md](DECISIONS.md) ADR-013 — Phase 2 전략 + 거부 항목
- [sowing-docs/EVALUATION.md](../sowing-docs/EVALUATION.md) — Karpathy 12 명제 평가
- [sowing-docs/background.md](../sowing-docs/background.md) — Sequoia Ascent 2026 발표
- [Model Context Protocol](https://modelcontextprotocol.io)
