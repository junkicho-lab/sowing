# Eval Corpus 스키마 (W13-T01)

> 본 코퍼스는 Phase 10~12 의 LLM 합성 기능을 검증하기 위한 한국어 교사 글 100건이다.
> ADR-013 의 verifiability 원칙: "LLM 기능은 Phase 10 검증 환경 위에 얹는다."

---

## 1. 디렉토리 구조

```
eval/corpus/
├── SCHEMA.md                          ← 본 문서
└── teacher_writings/
    ├── hand_crafted/   (10건)         ← 손으로 작성된 고품질 시드
    └── generated/      (90건)         ← 시드 변형 (학생 이름·과목 교체 등)
```

각 `.md` 파일 = 한 평가 케이스.

---

## 2. 파일 형식

```markdown
---
case_id: ent-001                    # 고유 ID. 형식: {task-prefix}-{3자리}
task: entity_extraction             # 평가 task type (§3 참조)
hand_crafted: true                  # true = 사람이 작성, false = 스크립트 생성
eval_dimensions: [factuality, coverage, format]
expected_output:                    # 기대 산출물 (gold standard, task별 형식 다름)
  students: [민준]
  subjects: [수학]
notes: 수학 평가 결과를 학생별로 분석한 사례  # (선택) 케이스 의도 설명
---

# (입력 — teacher's writing)
오늘 민준이가 수학 시간에...
```

frontmatter 필수 키: `case_id` / `task` / `hand_crafted` / `eval_dimensions` / `expected_output`.
선택 키: `notes`.

본문(`---` 다음): 평가 입력 — 한국어 교사가 실제로 쓸 법한 메모/필기/기록.

---

## 3. Task Types (6종)

각 task 는 LLM 합성 기능 하나에 대응. 입력·기대 출력·평가 차원이 다르다.

### 3.1 `entity_extraction` (Phase 11 EntityExtractor 검증)

- **입력**: 단일 entry (메모/필기/기록 본문)
- **기대 출력**: `{students: [...], subjects: [...], locations: [...]}` 의 entity 목록
- **평가 차원**: factuality (실제 등장한 entity 만), coverage (놓친 entity 없음), format (key 일치)
- **case_id prefix**: `ent-`

### 3.2 `student_digest` (Phase 11 StudentDigest 검증)

- **입력**: 한 학생을 다루는 여러 entries (5~15건)
- **기대 출력**: 학생당 1 마크다운 디제스트 (관찰 패턴·변화·후속)
- **평가 차원**: factuality (인용 출처 일치), conciseness (500~1500자), coverage (모든 entries 반영), tone (교사 입장의 따뜻함)
- **case_id prefix**: `dig-`

### 3.3 `gap_detection` (Phase 11 GapDetector 검증)

- **입력**: 학급 명단 + N주간 entries
- **기대 출력**: 미언급 학생 ID 배열
- **평가 차원**: precision (false positive 없음), recall (놓친 학생 없음)
- **case_id prefix**: `gap-`
- **결정적 task** — LLM 미사용. spec 의 contract test 로 100% 검증.

### 3.4 `reflection` (Phase 12 SemesterReflection 검증)

- **입력**: 한 학기 분량 entries (50~200건)
- **기대 출력**: 회고 마크다운 (자주 등장한 학생·주제·잘된 점·아쉬운 점·다음 학기)
- **평가 차원**: factuality, structure (필수 섹션 포함), conciseness (500~2000자), insight (단순 합산이 아닌 패턴)
- **case_id prefix**: `ref-`

### 3.5 `contradiction` (Phase 12 ContradictionDetector 검증)

- **입력**: 시간순 정렬된 entries 중 일부에 모순 (학생 묘사 변화·논리 비일관)
- **기대 출력**: `{detected: bool, type: "...", evidence: [{entry_id, quote}]}` 배열
- **평가 차원**: precision (false positive 없음), recall, evidence (인용 정확)
- **case_id prefix**: `con-`

### 3.6 `general` (한국어 일반 품질 평가)

- **입력**: 임의 한국어 교사 글
- **기대 출력**: 의미 변경 없이 다듬은 버전 또는 요약
- **평가 차원**: korean_consistency (높임말 일관성), factuality, conciseness, tone
- **case_id prefix**: `gen-`

---

## 4. 평가 차원 (Dimensions)

LLM-judge harness (W13-T02) 가 각 차원에 0~5점 부여.

| 차원 | 정의 |
|------|------|
| `factuality` | 입력에 없는 사실을 만들어내지 않음 (할루시네이션 0) |
| `coverage` | 입력의 핵심 정보 모두 반영 |
| `conciseness` | 불필요한 반복·장황 없음, 명시된 길이 범위 준수 |
| `relevance` | 출력이 task 의도에 부합 |
| `format` | 기대 출력 스키마(JSON 키, 마크다운 섹션 등) 일치 |
| `korean_consistency` | 높임말 통일, 한국식 일자, 한글 태그 |
| `tone` | 교사가 학생을 보는 따뜻하고 객관적인 톤 |
| `precision` | False positive 없음 (gap, contradiction 등에 적용) |
| `recall` | False negative 없음 |
| `evidence` | 인용 출처(entry_id, 본문 quote) 정확 |
| `insight` | 단순 합산을 넘어선 패턴·해석 (reflection, digest 등) |
| `structure` | 필수 섹션·헤딩 포함 |

각 task 의 `eval_dimensions` 필드는 적용 차원만 명시 — task 별로 평가 무관 차원은 제외.

---

## 5. 손으로 작성 vs 자동 생성

### `hand_crafted: true`

- 사람이 처음부터 작성한 고품질 시드 (~10건)
- 각 task type 대표 케이스 1~3건씩
- expected_output 도 사람이 직접 작성·검토

### `hand_crafted: false` (generated)

- `eval/scripts/generate_corpus.rb` 가 시드 + `templates/samples/*.md` 에서 파생
- 변형 규칙: 학생 이름 교체 / 과목 교체 / 날짜 shift / 카테고리 shuffle
- 빠르게 100건 채워 정량 검증의 base 제공
- 품질 한계 인정 — 진짜 검증은 hand_crafted 의 결과를 LLM-judge 로 보고, generated 는 회귀 자동화 base 로

---

## 6. 신규 케이스 추가 절차

1. 새 케이스 작성 (hand_crafted)
   - `case_id`: 다음 사용 가능 prefix-XXX
   - frontmatter 모든 필수 키 포함
   - `hand_crafted: true`
2. spec 실행 → contract 검증 통과 확인
3. PR 메시지에 task type + 추가 의도

옵트인 실 사용자 기여는 PR로 받음. 학생 이름은 가상명으로 치환 (개인정보 보호).

---

## 7. 코퍼스 사용처

- W13-T02 (LLM-judge harness): 각 case 의 expected_output vs 실제 LLM 출력 비교
- W13-T03 (CI eval): `bundle exec rake eval:run` 으로 회귀 측정
- W13-T04 (한국어 도메인 차원): korean_consistency 등 사람-judge 비교 카파 ≥ 0.8
- Phase 11~12: 각 task 도구의 기대 동작 표준
