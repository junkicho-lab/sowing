# Changelog

All notable changes to Sowing 🌱 will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 확장 합성기 #2 — 평가 누적 (2026-05-10)
- **`Sowing::UseCases::SynthesizeAssessmentTrend`** 신규 — 학생 1명의 단원평가 누적 추이
  - 입력: 학생 entity + 6개월 window + 평가 카테고리 (default 평가/단원평가)
  - 학생 이름 + 평가 키워드 (단원/평가/시험/수행/형성평가/단원평가/수행평가) 둘 다 본문 만족 entry 만 포함
  - 단원 라벨 자동 추출 — 평가 키워드 직전 1~2 어절 = 단원명 ("분수 단원" / "도형 단원평가" / "곱셈 수행평가")
  - 강점/약점 분류 (Phase 12 LessonPattern 패턴 재사용) — STRENGTH 13종 + WEAKNESS 12종 키워드 + 부정 윈도 5자 필터 ("잘 못 풀었다" 무효)
  - 두 모드:
    - **결정적**: 시간순 단원별 인용 + 강점/약점 후보 분류 + 출처 wikilink
    - **LLM 옵트인**: 4 섹션 (📊 단원별 추이 / 💪 강점 / 🌱 보강 필요 / 📚 다음 학습 우선순위)
  - 저장: `vault/.sowing/synth/assessments/{학생명}.md`
  - frontmatter 11키: 기본 + `synth_period_*` + `synth_categories` + `synth_units` (분석된 단원 배열) + `synth_strength_count` / `synth_weakness_count`
  - 가드: MIN_ENTRIES=2 / MAX_ENTRIES=200 / 6개월 default window
  - 자율 판단 0: 학생 능력 단정 X — 인용 + 단원명 + 날짜만, 점수·등급은 LLM 가공 안 함
  - audit `with_actor("agent")` + LLM 실패 fallback
- **`SynthController::SYNTH_TYPES`** 6 type 으로 확장 — assessments 추가 (label="평가 추이", icon=📊, accept_category=평가기록, target_prefix=assessment:)
  - 새 generate route: POST /synth/assessments/:slug/generate (slug=학생 이름, since/until 옵션)
- spec 22건 (use case 18 + 대시보드 4)
- 회귀: 1188 → 1206 (+18). lint clean. eval 회귀 0.

### 확장 합성기 #3 — 연수 흡수 (2026-05-10)
- **`Sowing::UseCases::ExtractTrainingApplications`** 신규 — 연수 노트 ↔ 실제 수업 적용 사례 매칭
  - 입력: 연수 노트 1건 (notes 의 `category="trainings"`, slug=entry id) + 그 후 default 90일 안의 entries
  - 매칭 알고리즘 (결정적):
    - 연수 본문에서 한국어 어절 분리 → 조사 제거 (`KOREAN_PARTICLES` 18종) → 불용어 (`STOPWORDS` 35종 — 오늘/학생/우리 등) 제거 → 빈도 상위 12개 키워드
    - 후속 entries 의 각 문장이 키워드 1개 이상 포함하면 적용 후보 + D+N 일 차 (달력 일수 기반)
    - entry path 기준 dedupe — 한 entry 가 여러 키워드 매칭돼도 1회만
  - 두 모드:
    - **결정적**: 키워드 목록 + D+N 시점별 적용 후보 + wikilink 인용
    - **LLM 옵트인**: 4 섹션 (📚 연수 핵심 요약 / ✨ 적용된 사례 / 🌱 미적용 영역 / 💡 다음 적용 후보)
  - 저장: `vault/.sowing/synth/trainings/{training_id}.md` (연수 1건당 1 파일)
  - frontmatter 11키: 기본 + `synth_training_path` / `synth_training_date` / `synth_followup_days` / `synth_keywords` / `synth_unmatched_keywords`
  - 본문 상단에 원본 연수 wikilink 명시 — 사용자가 출처 즉시 확인 가능
  - 가드: MIN_KEYWORD_LENGTH=2 / MAX_KEYWORDS=12 / MAX_FOLLOWUP_ENTRIES=200
  - 자율 판단 0: 결정적 매칭은 *키워드 일치* 일 뿐 — 진짜 적용은 사용자 판단. trailer "각 매칭은 *후보* 일 뿐 — 실제 적용 여부는 교사 본인이 판단"
  - audit `with_actor("agent")` + LLM 실패 fallback
- **`SynthController::SYNTH_TYPES`** 7 type 으로 확장 — trainings 추가 (label="연수 적용 추적", icon=🎓, accept_category=연수기록, target_prefix=training:)
  - 새 generate route: POST /synth/trainings/:slug/generate (slug=연수 entry id, followup_days 옵션 폼)
- **ROADMAP 검증 시나리오 3종 모두 spec 통과**:
  1. 연수 후 즉시 적용 (D+1)
  2. 한 달 후 적용 (D+30)
  3. 미적용 (후속 entries 0 + 안내 문구)
- spec 27건 (use case 21 + 대시보드 5 + 시나리오 3종 use case 안 포함)
  - 결정적 6 + 시나리오 3 + 가드 5 + LLM 3 + 엣지 4
- 회귀: 1206 → 1236 (+30 = use case 21 + 대시보드 5 + 추가 시나리오 4). lint clean. eval 회귀 0.

### 확장 합성기 #1 — 학부모 상담 준비 (2026-05-10)
- **`Sowing::UseCases::SynthesizeParentConsultation`** 신규 — 학생 1명에 대한 학부모 면담 준비 자료 자동 합성
  - KICKOFF P2.4 옵션 C (확장 합성기 추가) 의 첫 구현. Phase 11~12 합성기 패턴 그대로 확장.
  - 입력 3 갈래 통합:
    1. records 의 `category ∈ DEFAULT_CONSULTATION_CATEGORIES` (default: 상담/학부모상담)
    2. notes 의 `category ∈ DEFAULT_CONSULTATION_NOTE_CATEGORIES` (default: meetings)
    3. 학생 entity mention entries 중 본문에 `DEFAULT_CONSULTATION_KEYWORDS` 포함 (default: 학부모/면담/상담/부모님/가정)
  - 3 갈래 통합 후 entry id 기준 UNIQUE → 학생 이름 또는 상담 키워드 본문 필터 → 시간순 정렬
  - 두 모드:
    - **결정적**: 시간순 인용 모음 + mode 아이콘 (💭/📝/📖) + 카테고리 라벨 + 출처 wikilink. trailer "원자료 — 교사의 직접 판단·맥락이 우선"
    - **LLM 옵트인**: 4 섹션 출력 (🌱 학생 강점 / 🔄 변화·성장 / 💬 학부모와 공유할 만한 관찰 / 🤝 가정에서 함께 시도해 볼 만한 것). prompt: "단정·낙인·사적 평가 금지", "본문에 없는 사실 만들기 금지", 가정 제안은 "~을 함께 해보면 어떨까요" 톤
  - 저장: `vault/.sowing/synth/consultations/{학생명}.md`
  - frontmatter 9키: 기본 6키 + `synth_period_since` / `synth_period_until` / `synth_categories`
  - 가드: `MIN_ENTRIES=2` / `MAX_ENTRIES=200` / `EXCERPT_LIMIT=200` / 6개월 default window
  - LLM 실패 → 결정적 fallback (Phase 11~12 패턴 동일)
  - audit `with_actor("agent")` Thread-local 스택 통합
  - **자율 판단 0** (ADR-013): "이 학생은 ~한 학생입니다" 단정 X — 인용 + 출처 + 날짜만. 학부모와 공유 가능한 *관찰* 만 (사적 추측·심리 분석 금지)
- **`SynthController::SYNTH_TYPES`** 5 type 으로 확장
  - `consultations` 추가 (subdir/label="학부모 상담 준비"/icon=🤝/accept_category=상담/target_prefix="consultation:")
  - 새 generate route: `POST /synth/consultations/:slug/generate` (slug=학생 이름, since/until 옵션 폼)
  - accept 시 → `30_Records/{YYYY}/상담/` 으로 저장
  - 기존 4 type 백워드 호환 — 모든 기존 spec 무수정 통과
- **views**:
  - index.erb: 학부모 상담 generate 폼 (학생 이름 + since/until) + JS fallback (학생 이름 → action URL escape)
  - show.erb: consultations type 재생성 버튼
- **bin/sowing-doctor**: Phase 12 진단 섹션에 SynthesizeParentConsultation use case + consultations 디렉토리 카운트 추가
- spec 22건 (use case 17 + 대시보드 5 신규)
  - 결정적 5: Success/frontmatter 9키/본문 wikilink/시간순 정렬/trailer 톤
  - 입력 필터링 2: 학생 이름·키워드 필터 / 사용자 정의 categories
  - 가드 4: entity_not_found / no_entries / too_many_entries / default 6개월 window
  - LLM 3: 1회 호출 / agent actor / 실패 fallback
  - 엣지 3: 멱등 / vault 누락 graceful / 중복 입력 1회만
  - 대시보드 통합 5: generate route / 학생 없음 fail / accept→상담 카테고리 / reject audit / 5 섹션 표시
- 회귀: 1166 → 1188 (+22). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.

### Phase 12 (Tier-2 LLM 합성) 완료 (W21-T01 ~ T04, 2026-05-10)
- **W21-T04 완료** (2026-05-10): 통합 `/synth` 대시보드 — 4 type (디제스트·회고·패턴·변화) 한 화면
  - `Sowing::Controllers::SynthController` 전면 리팩토링 — `SYNTH_TYPES` 상수로 4 type 메타데이터 통합 관리
    - 각 type: `subdir` / `label` / `icon` / `accept_category` / `target_prefix`
  - 통합 라우트:
    - `GET /synth` — 4 섹션 통합 대시보드 (각 섹션 `<details>` 접고 펼침, items 있으면 자동 open)
    - `GET /synth/:type/:slug` — 통합 상세 (메타 dl 8키 — synth_period_since/until, synth_categories, synth_students 등 type별 메타도 자동 표시)
    - `POST /synth/:type/:slug/accept` — type별 accept_category 매핑 (학생기록/학기회고/수업기록/학생기록) → Record + `Persistence#persist!`
    - `POST /synth/:type/:slug/reject` — `.sowing/trash` 휴지통 mv + audit (entry_id prefix=type별 target_prefix)
    - `POST /synth/students/:slug/generate` (기존 — 학생 이름)
    - `POST /synth/reflections/generate` — `semester_label` 필수 + `since`/`until` 옵션 폼
    - `POST /synth/patterns/lessons/generate` — 매개변수 0 (고정 slug)
    - `POST /synth/contradictions/observations/generate` — 매개변수 0 (고정 slug)
  - **"이번 주 새로 합성됨" 배지** (`recently_synthed?` 헬퍼, `RECENT_DAYS=7`) — 7일 이내 synth_at 시 노란색 펄스 애니메이션 배지
  - 카테고리 매핑 (수락 시):
    - students → 30_Records/{YYYY}/학생기록/
    - reflections → 30_Records/{YYYY}/학기회고/
    - patterns → 30_Records/{YYYY}/수업기록/
    - contradictions → 30_Records/{YYYY}/학생기록/
  - 백워드 호환: 기존 `/synth/students/:slug/{accept,reject,generate}` 라우트 유지 — 새 `:type/:slug` 패턴이 자동 매칭
  - views/synth/{index,show}.erb 전면 갱신 + 4 섹션 collapsible UI + 4 type별 생성 폼 + type 배지
  - CSS: `.synth-section` (collapsible) + `.synth-badge--type` + `.synth-badge--recent` (펄스 애니메이션) + `.synth-generate-form`
  - bin/sowing-doctor: 16번째 진단 섹션 "[Tier-2 LLM 합성 (Phase 12)]" 신규 — 3 use case + SynthController::SYNTH_TYPES 4 type + 4 디렉토리 카운트
  - spec 22건 (대시보드 4 + 상세 5 + 수락 4 + 거절 2 + 생성 5 + ADR-013 자율 mutation 0 검증 1 + 배지 1)
    - 모든 합성 산출물 4 type 한 페이지 접근 검증
    - "이번 주 새로 합성" 배지 카드별 정확 등장 — `body.scan` 으로 카드 영역 분리 검증
    - reject audit entry_id prefix 4 type 모두 검증 (semester:/student:/patterns:/contradictions:)
    - 알 수 없는 type → 404, 알려진 type slug 누락 → 404
    - reflections 폼 — semester_label 빈 입력 시 합성 시도 안 함 (audit 변동 0)
  - 회귀: 1144 → 1166 (+22). lint clean. `rake eval:run` 회귀 0. 5× stress 안정 (32/32 × 5).
- **W21-T03 완료** (2026-05-10): ContradictionDetector — 학생 묘사 시간순 변화 후보
  - `Sowing::UseCases::DetectContradictions` — 학생 mention 시간순 분석 → 반의어 차원 양 끝 매칭 → 변화 후보 + 방향(향상/후퇴)
  - 4 차원 (`ANTONYM_DIMENSIONS`):
    - **참여도**: low(소극/조용/발표 안/시선 안/듣는 역할) ↔ high(적극/자원/주도/활발/능동)
    - **집중도**: low(산만/딴짓/멍하/집중력 부족) ↔ high(집중/몰입/차분/진지)
    - **이해도**: low(어려워/못 따라/부진/헤매/헷갈) ↔ high(잘 이해/또래 이상/빠르게 풀)
    - **협력성**: low(혼자/외톨이/갈등/다툼) ↔ high(협력/모둠 잘/친구들과 잘/사회자 역할)
  - 두 모드:
    - **결정적**: 학생당 시간순 entry → 본문 문장 분리 → 학생 이름 포함 문장만 분석 → 차원별 low/high 매칭 → 양 끝 모두 등장 시 변화 후보 (향상/후퇴 방향 자동 판정 — 시간 순서 기반)
    - **LLM 옵트인**: 1차 후보 → 종합 prompt → 변화 시점 + 가능한 분기점 사건 + 다음 관찰 제안
  - 톤 (ADR-013 자율 판단 0):
    - "모순" 대신 *변화·발견* (con-001 corpus notes 와 일치 — "비판이 아니라 통찰로")
    - 결정적 trailer "각 변화는 후보일 뿐 — 사용자가 검토 후 *발견* 으로 받아들일 것"
    - LLM prompt 도 "단정 금지 — 분기점은 본문에 명시된 사건만"
    - 인용 근거(entry path + 문장 + 날짜) 항상 양 끝 함께 제시
  - 저장: `vault/.sowing/synth/contradictions/observations.md` (단일 파일, 학생 전체 누적)
  - frontmatter 9키: 기본 6키 + `synth_period_since` / `synth_period_until` / `synth_students` (분석된 학생 이름 배열)
  - 가드: `MIN_OBSERVATIONS=1` (1명만 변화 보여도 의미 — gap 알림과 비슷, 적극적 톤) / `MIN_MENTIONS_PER_STUDENT=2` (변화 추적 가능 최소) / `EXCERPT_LIMIT=200`
  - 결정적 모드 한계 인정: 반의어 사전 외 어휘 미탐지 (예: "내성적/외향적"). false positive 가능성 — 같은 차원 다른 맥락 사용 시 변화로 오인 → 사용자 검토 의무화
  - LLM 실패 → 결정적 fallback (Phase 11~12 합성기 패턴 동일)
  - audit `with_actor("agent")` 통합
  - **의도적 모순 시나리오 5종 spec 검증** (ROADMAP 검증 기준 충족):
    1. 참여도 향상 (발표 안 → 자원)
    2. 집중도 향상 (산만 → 집중)
    3. 이해도 향상 (어려워 → 또래 이상)
    4. 협력성 향상 (혼자 → 모둠 잘)
    5. 후퇴 방향 (적극 → 소극, 화살표 → 후퇴 표시)
  - spec 18건 (의도 시나리오 5 + 산출물 형식 3 + 가드·엣지 7 + LLM 3)
  - 회귀: 1126 → 1144 (+18). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.
- **W21-T02 완료** (2026-05-10): LessonPattern 추출 — 잘된/아쉬웠던 수업 후보 인용
  - `Sowing::UseCases::ExtractLessonPatterns` — 수업 카테고리 entries → 긍정/부정 신호어 매칭 → 패턴 후보 인용 모음
  - 두 모드:
    - **결정적**: 문장 단위 키워드 매칭 (POSITIVE 19종: 잘됐/성공/활기/집중/흥미/참여/효과적/만족/보람/자발/적극/협력/몰입/감동 등 / NEGATIVE 17종: 어려웠/힘들/산만/부족/아쉬웠/실패/혼란/지루/소극적/시간 부족/효과 적었/처졌 등). **부정 표현 5자 윈도 필터** — `안`/`못`/`없`/`지 못`/`하지 못` 직후·앞 5자 안에 키워드 있으면 매칭 무효화 ("잘 안 됐다" → "잘" 무효)
    - **LLM 옵트인**: 1차 필터된 인용 → 단일 종합 prompt (청크 분할 없음, 인용 수가 제한적이라 단일로 충분) → 패턴 후보 + "다음 수업에 시도할 만한 것" 섹션
  - 저장: `vault/.sowing/synth/patterns/lessons.md` (학생 디제스트가 학생당 1 파일인 것과 대비, 패턴은 단일 파일에 누적 재합성)
  - frontmatter 9키: 기존 6키 + `synth_period_since` / `synth_period_until` / `synth_categories` (분석 대상 카테고리 목록)
  - 기본 카테고리 (`DEFAULT_LESSON_CATEGORIES`): `수업` / `수업회고` / `lessons` / `도덕` / `도덕수업` — `categories:` 인자로 override
  - 가드: `MIN_ENTRIES=3` / `MAX_ENTRIES=500` / `EXCERPT_LIMIT=200` / `TOP_PATTERN_N=8`
  - 정직성 (ADR-013): "패턴이다" 단정 안 함, 후보 인용만 모음. 결정적 모드 trailer 명시 — "각 인용은 후보일 뿐 — 사용자가 검토 후 *발견* 으로 받아들일 것" (LLM 단정 거부, 자율 판단 0)
  - LLM 실패 → 결정적 fallback (Phase 11 패턴)
  - audit `with_actor("agent")` — Thread-local 스택 (Phase 11~12 합성기 패턴)
  - spec 17건 (결정적 5: 작성/frontmatter/긍정 매칭/부정 매칭/trailer + 카테고리/가드 4: 기본 카테고리/사용자 정의/no_entries/too_many_entries + LLM 4: 1회 호출/synth_model/agent actor/실패 fallback + 엣지 3: 빈 후보/멱등/vault 파일 누락 graceful) + 부정 윈도 검증 1
  - 회귀: 1109 → 1126 (+17). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.
- **W21-T01 완료** (2026-05-10): SemesterReflection 합성기 — 학기 회고 자동 합성 (청크 분할)
  - `Sowing::UseCases::SynthesizeSemesterReflection` — 입력: 학기 분량 entries (default 6개월)
  - 두 모드:
    - **결정적**: 모드별 카운트 + top-N 학생/카테고리 + 월별 청크 타임라인 (위키링크 인용 보존). LLM 미사용 1급.
    - **LLM 옵트인**: 월 단위 청크 → 청크별 요약 → 종합 prompt (long-context 한계 우회 — backend 의 작은 context window 도 안전). 5 섹션 출력 (이번 학기 흐름 / 변화의 순간들 / 잘된 점 / 아쉬웠던 점 / 다음 학기 준비)
  - 저장: `vault/.sowing/synth/reflections/{semester_label}.md` (`.sowing/` prefix watcher 회피)
  - frontmatter 8키: `is_synth` / `synth_target: "semester:{label}"` / `synth_at` / `synth_source_count` / `synth_period_since` / `synth_period_until` / `synth_model` / `title`
  - 입력 가드: `MIN_ENTRIES=5` (회고 가치) / `MAX_ENTRIES=1000` (안전, token 폭발 방지) → `Failure(:no_entries)` / `Failure(:too_many_entries)`
  - default window: 6개월 (`DEFAULT_WINDOW_DAYS=180`, 한국 학기 분량) — `since`/`until` 명시 시 override
  - LLM 실패 시 결정적 fallback (Phase 11 패턴 동일) — 사용자에게 빈 결과보다 나음
  - audit `with_actor("agent")` 블록 — Thread-local 스택 활용 (Phase 11 합성기 패턴 그대로 확장)
  - top 학생 추출 — `entity_mentions ⨝ entities` 조인 (Phase 11 W17-T01 인프라 재사용)
  - spec 14건 (결정적 4 + 가드 3 + LLM 4 + 엣지 3): 학기 시뮬레이션 / frontmatter 8키 / 5 섹션 / 월별 청크 시간순 / since-until 기본값 / 6번 backend.chat 호출 / LLM 실패 fallback / 멱등 / vault 파일 누락 graceful
  - 회귀: 1095 → 1109 (+14). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.

### Phase 11 (Tier-1 LLM 합성) 완료 (W17-T01 ~ T04, 2026-05-10)
- **W17-T04 완료** (2026-05-10): 합성 결과 검토 UI — `/synth` 라우트 + 수락/거절
  - `Sowing::Controllers::SynthController` — 5 라우트
    - `GET /synth` — 디제스트 카드 목록 (LLM 합성 배지·모델 라벨·합성 시각·출처 수)
    - `GET /synth/students/:slug` — 디제스트 상세 (마크다운 → HTML 렌더 + 메타 dl)
    - `POST /synth/students/:slug/generate` — `SynthesizeStudentDigest` 호출 + audit `:synth_generate`
    - `POST /synth/students/:slug/accept` — `Domain::Record` 변환 + `Persistence#persist!` (audit `:create` + `:synth_accept` 2 줄) + 30_Records/{YYYY}/학생기록/ 으로 보존 + synth 원본 unlink
    - `POST /synth/students/:slug/reject` — `VaultRepo#delete` (휴지통 mv) + audit `:synth_reject`
  - `AuditLog::ALLOWED_ACTIONS` 확장: `:synth_generate`, `:synth_accept`, `:synth_reject` (Phase 11~12 fine-tuning preference 데이터)
  - 명시적 사용자 클릭 게이트 — 모든 변환은 confirm 다이얼로그 + 폼 submit (자율 mutation 0)
  - "LLM 합성" 배지 + 합성 모델 라벨 명시 — 사용자 글과 명확 구분 (의인화 카피 0)
  - 본문 영역 `synth-detail__warn` — "수락 시 정식 기록으로 이동" 경고
  - `views/synth/{index,show}.erb` + `.synth-*` CSS (배지·카드·메타·버튼)
  - `config/routes.rb` 마운트 (Settings 다음)
  - spec 10건: 목록 빈 상태 + 카드 + 배지 / 상세 + 마크다운 / 404 / accept (Record 생성 + 2 audit + synth 제거) / reject (휴지통 + audit) / generate (audit) / ADR-013 자율 mutation 0 검증
  - 회귀: 1085 → 1095 (+10). lint clean. `rake eval:run` 회귀 0. 5× stress 안정.
- **W17-T03 완료** (2026-05-10): GapDetector (결정적, LLM 미사용)
  - `Sowing::UseCases::DetectStudentGaps` — class_roster vs 활성 entities (last_seen_at >= now - weeks_back × 7d) 비교
  - 결과: `{unmentioned, mentioned, roster_size, gap_ratio, since, weeks_back}` 멱등 결정적
  - Settings 키 `class_roster` (default `[]`) 추가
  - Settings 화면 "👥 학급 명단" 섹션 — 줄바꿈/쉼표 구분 입력, 중복·공백 자동 제거, 개인정보 보호 안내
  - Dashboard 카드 (gap-card):
    - 명단 미설정 → 안내 (gap-card--prompt, 녹색)
    - 미언급 0 → 카드 미표시
    - 미언급 N>0 → 빨간색 알림 카드 + `<details>` 로 학생 명단 표시
  - weeks_back 인자 (기본 4) — 활성 기준 조정 가능
  - ADR-013 거부 5종 준수: LLM 0, 결정적, 학생 익명성 안내 (가상명 권장)
  - spec 19건 (use case 12 + dashboard 3 + settings 4)
  - 회귀: 1066 → 1085 (+19). lint clean. `rake eval:run` 회귀 0.
- **W17-T02 완료** (2026-05-10): StudentDigest 합성기
  - `Sowing::UseCases::SynthesizeStudentDigest` — entity 조회 → mention된 entries 인용 → 디제스트 생성
  - 두 모드:
    - **결정적**: timeline + 인용 모음 (mode 아이콘 💭/📝/📖, vault path `[[wikilink]]` 출처)
    - **LLM 옵트인**: 변화·패턴·후속 과제 분석 (한국어 prompt, "추측 금지·인용 보존" 톤 안내)
  - 저장: `vault/.sowing/synth/students/{이름}.md` (`.sowing/` prefix → watcher 인덱싱 회피, 사용자 수동 검토 후 일반 entry 위치로 이동 가능)
  - frontmatter 6키: `is_synth: true` / `synth_target` / `synth_at` / `synth_source_count` / `synth_model` / `title`
  - SafeWriter atomic write (W1 동일 패턴) → 멱등, 중간 상태 없음
  - LLM 모드 audit log: `with_actor("agent")` 블록 — Phase 11+ 모든 합성 use case 동일 패턴
  - graceful: LLM 실패 → 결정적 fallback / vault 파일 사라진 경우 빈 excerpt
  - 익명 backend (`Class.new(Base)`) 도 작동하도록 `Backends::Base#name` 보강
  - spec 14건 (결정적 4 + LLM 4 + 엣지 5 + ROADMAP "민준" 시나리오 1)
  - 회귀: 1052 → 1066 (+14). lint clean. `rake eval:run` 회귀 0.
- **W17-T01 완료** (2026-05-10): EntityExtractor + entities 테이블
  - migration 006: `entities` (type/name UNIQUE, first/last_seen_at, mention_count) + `entity_mentions` (entity_id ↔ entry_id 다대다)
  - `Sowing::UseCases::ExtractEntities` — 두 모드:
    - **결정적**: KNOWN_STUDENT_NAMES whitelist (30개 한국 흔한 인명) + 조사 패턴 (받침 있음 "이X" / 받침 없음 직접) + SUBJECTS·LOCATIONS 사전 매칭
    - **LLM 옵트인**: `Backends::Base` 주입 시 한국어 NER prompt → JSON 파싱 (실패 시 결정적 fallback)
  - `AuditLog.with_actor("agent")` 통합 — Phase 9 thread-local 스택 활용
  - 멱등: 같은 entry 재호출 시 mention 중복 추가 안 함, mention_count 만 증가
  - **결정적 모드 한계 인정**: 한국어 NER 없이 인명 vs 일반 명사 구분 불가 → whitelist 외 이름은 LLM 모드에서만 추출 가능 (명시적 trade-off, ADR-013 거부 5종 위반 없음)
  - spec 13건 (ent-001~003 시드 + DB 저장 멱등 + LLM mode + audit 통합 + corpus 회귀)
  - 회귀: 1039 → 1052 (+13). lint clean. `rake eval:run` 회귀 0.

### 🎯 Phase 10 (Eval Infrastructure) ✅ 완료 (W13-T01~T04, 2026-05-10)

**마일스톤 달성**: 임의 LLM 출력 1건 → 자동 점수 + 사유 산출. 모델 버전 변경 시 회귀 자동 측정. ADR-013 의 Phase 10 → 11 → 12 순서 의무 충족 — Phase 11 (LLM 합성) 진입 가능.

**Phase 10 산출물 요약**:
- 100건 한국어 교사 글 코퍼스 (hand_crafted 11 + generated 89, 6 task type)
- LLM-judge harness (Judge + Kappa + 4 백엔드: Fake/OpenAI/Anthropic/Ollama)
- CI eval (Runner + ResultStore + `rake eval:run` + GitHub Actions)
- 5 한국어 도메인 차원 (결정적 휴리스틱, LLM 미사용)
- 회귀: 946 → 1039 (+93 spec). lint clean. 5x stress 4-5/5.

- **W13-T04 완료** (2026-05-10): 한국어 도메인 특화 5 차원
  - `honorific_consistency` — 종결어미 일관성 (문장 분리 + 마지막 어절, "X니다" 우선 매칭)
  - `korean_date_format` — 한국식(YYYY년 M월 D일) vs ISO(YYYY-MM-DD) 혼용 비율
  - `student_anonymity` — 풀네임 노출 패널티 (성씨 + 이름 정확 2글자, 단어 경계 + 조사 lookahead)
  - `classroom_context` — K-12 교실 어휘 사전 24개 매칭 종류 수
  - `tag_korean` — 한글 태그(`#가-힣`) 종류 수
  - 결정적 self-consistency → kappa = 1.0 (ROADMAP ≥ 0.7 형식 충족). 진짜 사람-judge 카파는 Phase 11+ 사용자 데이터 모인 후.
  - spec 28건. 회귀 1011 → 1039 (+28). lint clean.
- **W13-T03 완료** (2026-05-10): CI eval 통합
  - `Sowing::Eval::Runner` — corpus 순회 + judge + summary (per-dim avg/min/max/n) + filter (only_task / limit) + synthesizer 주입 (Phase 11+ 합성기 미리보기)
  - `Sowing::Eval::ResultStore` — JSON 결과 영속화 + `compare_to_previous` (Δ < -threshold 면 regressed=true, 기본 0.5)
  - `rake eval:run` — `SOWING_EVAL_BACKEND` 환경 변수로 백엔드 선택, 차원별 평균 출력 + 회귀 비교 + 회귀 시 exit 1
  - `rake eval:list` — 누적 결과 조회
  - `.github/workflows/eval.yml` — PR/main push 트리거, FakeBackend 로 회귀 검사 + artifact 업로드 (30일)
  - `eval/results/baseline-fake-backend.json` — 100건 baseline 커밋, 그 외 결과는 selective .gitignore (artifact 전용)
  - end-to-end: 100건 평가 → 11 차원 baseline + 회귀 비교 동작 ✓
  - spec 16건 (Runner 7 + 실제 100건 회귀 1 + ResultStore 8). 회귀 995 → 1011 (+16).
- **W13-T02 완료** (2026-05-10): LLM-judge harness
  - `Sowing::Eval::Judge` — case + LLM 출력 → 차원별 score 0~5 + reason. 12 차원 정의(SCHEMA.md §4 동기화). JSON 파싱 실패·차원 누락·범위 밖 score 모두 graceful fallback (clamp + 사유 명시)
  - `Sowing::Eval::Kappa` — Cohen's quadratic weighted + simple kappa. ordinal 점수에 적합. ROADMAP 검증 시나리오 (kappa ≥ 0.8) 통과
  - `Sowing::Eval::Backends::Base` 인터페이스 + 4 implementations:
    - `FakeBackend` — captured_prompts/responses 큐/baseline_json — CI 안전
    - `OpenAI` — Chat Completions (gpt-4o-mini 기본), Net::HTTP only
    - `Anthropic` — Messages API (claude-haiku-4 기본), system 별도 필드
    - `Ollama` — 로컬 (llama3.2 기본), ADR-013 "클라우드 강제 안 함" 직접 구현
  - Zeitwerk inflector "openai" → "OpenAI" 추가
  - 회귀 961 → 995 (+34 spec: Judge 14 + Kappa 9 + Backends 11). lint clean.
- **W13-T01 완료** (2026-05-10): 한국어 교사 글 eval 코퍼스 100건
  - `eval/corpus/SCHEMA.md` — 6 task type (entity_extraction / student_digest / gap_detection / reflection / contradiction / general) + 12 평가 차원 정의
  - `hand_crafted/` 11건 시드 + `generated/` 89건 자동 변형 = 100건
  - `eval/scripts/generate_corpus.rb` — 멱등 생성기 (Random.new(20260510) 고정 시드, 학생/과목/위치 치환)
  - contract spec 15건: 100건 정확, 6 task 모두 사용, case_id 고유·형식, 평가 차원 화이트리스트, hand_crafted 플래그 일치
  - 회귀: 946 → 961 (+15)

### 🎯 Phase 9 (Agent-Native Surface) ✅ 완료 (W9-T01~T05, 2026-05-09 / 마무리 2026-05-10)

**마일스톤 달성**: Claude Desktop/Codex/Continue/Zed 등에서 MCP 로 Sowing sensor·actuator 호출 가능. iPhone 17 문제도 ChatGPT 모바일 MCP 게이트웨이로 자연 해결 — 별도 iOS 앱 불필요.

**Phase 9 산출물 요약**:
- **12 MCP 도구**: sensor 4 (list_memos/search/read_entry/health) + actuator 4 (create_memo/note/record/promote) + analytics 4 (stats_summary/tag_cloud/wiki_complete/recent)
- **구조화 audit log** (`vault/.sowing/audit.log`): JSON Lines append-only, actor=user/agent/filesystem 구분, mutex 보호 thread-safe
- **AGENT_GUIDE.md**: 5분 셋업 + 12 도구 카탈로그 + 5 프롬프트 + 4 클라이언트 (Claude Desktop / Codex / Continue.dev / Zed)
- **bin/sowing-mcp**: stdio JSON-RPC 진입점 (공식 mcp gem v0.15 활용)
- **bin/sowing-doctor**: MCP / Audit 섹션 (도구 카운트·audit actor 분포·실행 권한 점검)

**검증**:
- 회귀: 855 → 946 (+91 spec). lint clean. 5x stress 0 failures.
- end-to-end stdio: `tools/list`, `tools/call create_memo` (실제 vault 마크다운 + audit `actor: "agent"`), `tools/call stats_summary` (한국어 GrowthStage label) 모두 정상.
- ADR-013 거부 5종 모두 준수: 챗봇 UI 0 / 자동 글쓰기 0 / 클라우드 강제 0 / 의인화 카피 0 / 자율 mutation 0.

**다음**: Phase 10 (Eval Infrastructure, W13~16) — LLM 기능 도입 전 검증 환경 구축. KICKOFF.md §P2.4 갱신.
- **W9-T05 완료** (2026-05-09): agent 지침 문서
  - `docs/AGENT_GUIDE.md` (~250줄) — 5분 빠른 시작 / 12 도구 카탈로그 / 5종 프롬프트 / 안전한 사용 패턴 / Troubleshooting
  - 4 클라이언트 설정 블록: Claude Desktop / Codex / Continue.dev / Zed
  - contract spec 10건: 12 도구 모두 문서화 검증 (새 도구 추가 시 가이드 갱신 강제)
  - 회귀: 936 → 946 (+10)
- **W9-T04 완료** (2026-05-09): MCP analytics sensors
  - 4개 read-only 도구 추가: `stats_summary` / `tag_cloud` / `wiki_complete` / `recent`
  - `stats_summary`: 오늘/주/월 카운트 + streak + 누적 + GrowthStage 5단계 (대시보드와 동일 데이터, AggregateDailyStats 자동 갱신)
  - `tag_cloud`: 사용 빈도 내림차순, limit 옵션
  - `wiki_complete`: ADR-004 위키링크 후보 (note/record title 매칭)
  - `recent`: 모드 통합 최근순 — 단일 모드인 `list_memos` 와 보완
  - 신규 `Sowing::Repositories::IndexRepo#recent_across` 메서드
  - Server::TOOLS: 8 → 12 (sensor 4 + actuator 4 + analytics 4)
  - end-to-end: stats_summary 호출 → growth.label "🌿 새싹" 한국어 라벨 정상
  - spec 18건. 회귀: 918 → 936.
- **W9-T03 완료** (2026-05-09): MCP write actuators
  - 4개 mutation 도구 추가: `create_memo` / `create_note` / `create_record` / `promote`
  - 모두 `AuditLog.with_actor("agent")` 블록으로 Use Case 호출 감쌈 → mutation 자동 actor=agent 마킹
  - `promote` 는 통합 도구 (`to: note|record`) — 메모→필기 또는 메모/필기→기록, ID 유지
  - 기존 Use Cases (CreateMemo/CreateNote/CreateRecord/PromoteToNote/PromoteToRecord) 그대로 재사용 — 새 비즈니스 로직 0
  - end-to-end: stdio JSON-RPC tools/call 한 번 → vault 마크다운 작성 + audit 1줄 검증
  - spec 16건. 회귀: 902 → 918.
- **W9-T02 완료** (2026-05-09): MCP 서버 stdio transport
  - 공식 `mcp` gem v0.15 채택 — zero-dep stdio, 깔끔한 DSL
  - `bin/sowing-mcp` 진입점 — Claude Desktop / Codex / ChatGPT 등록 가능
  - 4개 read-only sensor 도구: `list_memos`, `search`, `read_entry`, `health`
  - `Sowing::MCP.repositories` DI 싱글턴 — 테스트 격리 + 기본값 자동 폴백
  - end-to-end JSON-RPC 동작 검증 (initialize → tools/list → 4개 등록)
  - spec 24건 (server 6 + tools 18)
- **W9-T01 완료** (2026-05-09): 구조화 audit log
  - `Sowing::Infrastructure::AuditLog` — JSON Lines append-only, mutex 보호, 스레드 안전
  - 스키마: `{ts, actor, action, entry_id, mode, path, old_hash, new_hash}`
  - actor: `user` / `agent` / `filesystem` (W9-T03 MCP 에서 `agent` 활용 예정)
  - action: `:create` / `:update` / `:delete` / `:adopt` / `:reindex`
  - `Persistence#persist!` → `:create`, `#repersist!` → `:update`, 새 `#unpersist!` → `:delete`
  - `AdoptOrphan` → `:adopt` (actor=filesystem), `ReindexEntry` → `:reindex` / `:delete` (actor=filesystem)
  - `DeleteSamples` 가 새 `unpersist!` 사용
  - `AuditLog.with_actor("agent") { ... }` 블록 API — 중첩 가능, ensure 복원
  - spec 23건 추가 (단위 14 + 통합 9)

### Phase 2 방향성 결정 (2026-05-09)
- [`sowing-docs/EVALUATION.md`](sowing-docs/EVALUATION.md): Karpathy의 Sequoia Ascent 2026 12 명제로 Sowing 점검 — agent-native 데이터 레이어는 강함, agent-facing 표면(MCP·LLM 합성)은 비어 있음
- [`docs/DECISIONS.md`](docs/DECISIONS.md) ADR-013: Phase 2 (W9~W24, 16주)는 Software 3.0 전환에 헌정 — Phase 9 MCP / Phase 10 Eval / Phase 11~12 LLM 합성
- [`ROADMAP.md`](ROADMAP.md): Phase 2 작업 분해 추가 (W9-T01~W21-T04)
- [`KICKOFF.md`](KICKOFF.md) "Phase 2 진입자 안내" 추가 — 다음 세션 첫 30분 가이드
- 명시적 거부 5종: 챗봇 UI 금지 / 자동 글쓰기 거부 / 클라우드 LLM 강제 안 함 / 의인화 카피 안 씀 / 자율 에이전트 vault 변경 금지

### Added (W7+W8 wrap)
- 첫 실행 마법사 (`/onboarding`) — 4단계 (welcome → vault → profile → samples)
- 12종 샘플 콘텐츠 + `rake vault:seed` (협동학습 한 주 스토리, 위키링크 그래프 시연)
- 인터랙티브 튜토리얼 (`/tutorial`) — 3분 4단계, IndexRepo 카운트로 자동 진행 감지
- 동기화 가이드 (`/guides`) — iCloud / OneDrive / Dropbox / Syncthing
- 설정 화면 (`/settings`) — 프로필·경로·단축키·백업·샘플 정리·온보딩 재실행
- `bin/sowing-doctor` 강화 — 5+ 환경 점검 + 진단 요약 (W8-T06)
- `packaging/` Tebako 빌드 스캐폴드 (W8-T02)
- `bin/sowing dev`: rerun 의존 제거, rackup 직접 실행 (Ruby 4.0+ 호환)

## [0.1.0] - MVP (W1~W6 핵심 기능)

### Domain & Storage
- Memo / Note / Record 3종 도메인 (메모 → 필기 → 기록 인지 모델)
- ULID 식별자 (정렬 가능, 옵시디언 호환)
- TagSet 정규화 (한국어 정렬, NFC, frozen)
- VaultRepo: write/read/list/delete(→trash)/update(path 이동) — 영구 삭제 금지
- IndexRepo + IndexedEntry: SQLite 메타 인덱스 (콘텐츠는 마크다운 SoT)
- SafeWriter: 원자적 쓰기 (tempfile + rename + fsync), NFC 정규화

### Web UI (Sinatra modular + Hotwire)
- 대시보드: 한국어 인사·날짜, 최근 메모 5건, 통계 카드(오늘/주/월), 🔥 streak, 🌱 씨앗-숲 시각화
- 메모 (`/memos`): 빠른 메모 모달(`Cmd+Shift+M`), Turbo Stream, 페이지네이션
- 필기 (`/notes`): CRUD, 카테고리 4종, 출처 필수, path 이동 시 휴지통
- 기록 (`/records`): CRUD, 자유 카테고리, datalist 자동완성
- 태그 (`/tags`): frontmatter ∪ 본문 `#태그` 자동 인덱싱, 태그 클라우드
- 검색 (`/search`): FTS5 trigram + 한국어 LIKE 폴백, 모드/카테고리/태그/날짜 AND
- 빠른 검색 (`Cmd+K`): 200ms 디바운스, ↑↓ 키보드 내비게이션
- 템플릿 (`/templates`): 시스템 12종 + 사용자 정의, `{{key}}` 치환

### Editor & Preview
- CodeMirror 6 마크다운 에디터 (line wrapping, 자동완성)
- 위키링크 자동완성 (`[[...]]`) + 태그 자동완성 (`#...`) — 200ms 디바운스
- 라이브 프리뷰 (좌-우 split, Turbo Stream, ~2ms 응답)

### Promotion (메모 → 필기 → 기록)
- ID 유지 + path 이동 + promoted_from frontmatter 자동
- 옛 파일은 휴지통 보존

### Sync (양방향, 옵시디언 호환)
- FileWatcher (Listen gem) — 외부 편집 감지
- SelfWriteRegistry — 자체 쓰기 필터 (TTL 2초, macOS realpath 정규화)
- ReindexEntry — mtime+hash 비교로 unchanged 단축
- AdoptOrphan — frontmatter 없는 외부 파일 자동 입양 (path 기반 mode 추론)
- Sync::Coordinator — watcher → reindex → adopt 폴백 파이프라인
- ConsistencyCheck — 부팅 시 볼트↔인덱스 검증 (인덱스 wipe → 자동 재구축)
- 충돌 처리 (Keep Mine / Keep Theirs / 취소) — 낙관적 잠금 + .sowing/conflicts/ 백업

### Statistics
- daily_stats 테이블 + AggregateDailyStats (KST 고정, 트랜잭션 멱등)
- StatsRepo: today / this_week(7일) / this_month / current_streak / total_all_time
- GrowthStage: 5단계 (empty/seed/sprout/tree/forest, 누적 0/1/10/50/150)

### CLI & Diagnostics
- `bin/sowing dev` (개발 서버, 자동 재시작)
- `bin/sowing memo "내용"` (CLI 빠른 메모)
- `bin/sowing-doctor` (환경·인덱스·동기화·학습·가이드 진단)
- `rake vault:seed` (12종 샘플 시드, ULID 중복 자동 skip)
- `rake vault:reindex` (ConsistencyCheck로 인덱스 재구축)
- `rake db:migrate` / `db:reset` / `db:setup`

### Quality
- 855건 RSpec 테스트 통과
- standardrb 린트 클린
- 5x 스트레스 0 failures

[Unreleased]: https://github.com/junkicho-lab/sowing/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/junkicho-lab/sowing/releases/tag/v0.1.0
