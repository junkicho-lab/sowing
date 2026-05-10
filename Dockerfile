# Sowing 🌱 — 한국 교사용 로컬 우선 노트 도구
#
# 가장 빠른 설치 경로 — Tebako/외부 패키징 도구 불필요.
# 사용:
#   docker build -t sowing:latest .
#   docker run -p 48723:48723 -v ~/Documents/SowingVault:/vault \
#              -v sowing-data:/data sowing:latest
#
# 또는 docker-compose:
#   docker compose up -d
#
# 데이터 위치:
#   /vault     — 마크다운 SoT (호스트 폴더 마운트 권장)
#   /data      — DB 인덱스 + audit.log + settings (named volume 권장)

# ─── Stage 1: 빌드 의존성 ───
FROM ruby:3.3-slim AS builder

# Sowing Gemfile 은 Ruby ~> 4.0 이지만 ruby 4.0.3 docker image 가 부재 시점 →
# 3.3 (LTS) 로 빌드 검증. Ruby 4.x 정식 image 출시 후 변경 예정.

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      libsqlite3-dev \
      libyaml-dev \
      pkg-config \
      git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Gemfile 만 먼저 복사 → bundler 캐시 layer 활용
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true \
    && bundle config set --local without "development test" \
    && bundle install --jobs 4 --retry 3

# 전체 소스 복사
COPY . .

# ─── Stage 2: 런타임 ───
FROM ruby:3.3-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
      libsqlite3-0 \
      libyaml-0-2 \
      tzdata \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

# 한국어 locale 설정 (UTF-8 NFC)
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SOWING_ENV=production \
    SOWING_VAULT=/vault \
    SOWING_DATA_DIR=/data \
    PORT=48723

WORKDIR /app

# bundler 결과 + 소스 복사
COPY --from=builder /app /app
COPY --from=builder /usr/local/bundle /usr/local/bundle
RUN bundle config set --local deployment true \
    && bundle config set --local without "development test"

# 런타임 디렉토리 — 사용자가 마운트 안 해도 컨테이너 안에서 동작
RUN mkdir -p /vault /data

# 기본 포트 + 헬스체크
EXPOSE 48723

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD ruby -e "require 'net/http'; puts Net::HTTP.get(URI('http://127.0.0.1:#{ENV['PORT'] || 48723}/health'))" \
      || exit 1

# 첫 부팅 시 db:setup 자동 실행 후 rackup (0.0.0.0 바인딩 필수 — bin/sowing dev 는 127.0.0.1 hardcode)
# production 모드 puma 셋업은 SETUP.md 참조
CMD ["sh", "-c", "bundle exec rake db:setup 2>/dev/null; exec bundle exec rackup -p ${PORT} -o 0.0.0.0"]
