# frozen_string_literal: true

source "https://rubygems.org"
ruby ">= 3.3.0"

# === Core Web ===
gem "sinatra", "~> 4.0"
gem "sinatra-contrib", "~> 4.0"
gem "puma", "~> 6.4"
gem "rackup", "~> 2.1"
gem "rack-protection", "~> 4.0"

# === Data ===
gem "sequel", "~> 5.80"
gem "sqlite3", "~> 2.0"

# === Markdown / Files ===
gem "commonmarker", "~> 2.8"
gem "front_matter_parser", "~> 1.0"
gem "listen", "~> 3.9"

# === View Layer ===
gem "tilt", "~> 2.4"
gem "erubi", "~> 1.13"

# === i18n ===
gem "r18n-core", "~> 6.0"

# === Utilities ===
gem "dry-validation", "~> 1.10"
gem "dry-monads", "~> 1.6"
gem "zeitwerk", "~> 2.6"
gem "ulid", "~> 1.4"
gem "async", "~> 2.10"

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "rspec-its", "~> 1.3"
  gem "factory_bot", "~> 6.4"
  gem "standard", "~> 1.41"
  gem "pry-byebug", "~> 3.10"
end

group :development do
  gem "rerun", "~> 0.14"
  gem "rake", "~> 13.2"
end

group :test do
  gem "capybara", "~> 3.40"
  gem "rack-test", "~> 2.1"
  gem "timecop", "~> 0.9"
  gem "simplecov", "~> 0.22", require: false
end

group :production do
  # 패키징 단계에서만 활성화
  # gem "tebako", "~> 0.10"
end
