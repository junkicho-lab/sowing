# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::Infrastructure::Filesystem::SafeWriter do
  let(:tmpdir) { Pathname.new(Dir.mktmpdir("safe-writer-spec-")) }
  let(:writer) { described_class.new }
  let(:target) { tmpdir.join("test.md") }

  after do
    FileUtils.rm_rf(tmpdir) if tmpdir.exist?
  end

  def leftover_tempfiles(dir)
    dir.children.select { |p| p.basename.to_s.match?(/\.tmp\.[0-9a-f]+\z/) }
  end

  # 환경 locale이 UTF-8이 아닐 수도 있으므로 명시적 UTF-8로 읽는다.
  def read_utf8(path)
    File.read(path.to_s, encoding: "UTF-8")
  end

  describe "#atomic_write" do
    context "신규 파일을 쓸 때" do
      it "내용이 정확히 디스크에 기록된다" do
        writer.atomic_write(target, "Hello 🌱")
        expect(read_utf8(target)).to eq("Hello 🌱")
      end

      it "기록된 경로(Pathname)를 반환한다" do
        result = writer.atomic_write(target, "내용")
        expect(result).to be_a(Pathname)
        expect(result).to eq(target)
      end

      it "지정한 권한(mode)으로 저장된다" do
        writer.atomic_write(target, "x", mode: 0o600)
        expect(target.stat.mode & 0o777).to eq(0o600)
      end

      it "기본 권한은 0644이다" do
        writer.atomic_write(target, "x")
        expect(target.stat.mode & 0o777).to eq(0o644)
      end

      it "부모 디렉토리가 없으면 자동 생성한다" do
        nested = tmpdir.join("a/b/c/file.md")
        writer.atomic_write(nested, "내용")
        expect(read_utf8(nested)).to eq("내용")
      end

      it "path 인자로 String도 받는다" do
        writer.atomic_write(target.to_s, "x")
        expect(target).to exist
      end

      it "내용이 빈 문자열이면 빈 파일이 생성된다" do
        writer.atomic_write(target, "")
        expect(target).to exist
        expect(read_utf8(target)).to eq("")
      end

      it "성공 시 임시 파일은 남지 않는다" do
        writer.atomic_write(target, "내용")
        expect(leftover_tempfiles(tmpdir)).to be_empty
      end
    end

    context "기존 파일을 덮어쓸 때" do
      before { File.write(target, "예전 내용") }

      it "새 내용으로 원자적으로 교체된다" do
        writer.atomic_write(target, "새 내용")
        expect(read_utf8(target)).to eq("새 내용")
      end
    end

    context "쓰기 도중 강제 종료된 경우 (chaos)" do
      before { File.binwrite(target.to_s, "기존 내용") }

      it "rename 직전에 실패하면 기존 파일이 손상되지 않는다" do
        allow(File).to receive(:rename).and_raise(Errno::EIO, "simulated crash")

        expect { writer.atomic_write(target, "새 내용") }.to raise_error(Errno::EIO)
        expect(read_utf8(target)).to eq("기존 내용")
      end

      it "rename 실패 후 임시 파일은 정리된다" do
        allow(File).to receive(:rename).and_raise(Errno::EIO, "simulated crash")

        expect { writer.atomic_write(target, "새 내용") }.to raise_error(Errno::EIO)
        expect(leftover_tempfiles(tmpdir)).to be_empty
      end

      it "Interrupt(Ctrl+C)에도 임시 파일은 정리된다" do
        allow(File).to receive(:rename).and_raise(Interrupt)

        expect { writer.atomic_write(target, "새 내용") }.to raise_error(Interrupt)
        expect(leftover_tempfiles(tmpdir)).to be_empty
        expect(read_utf8(target)).to eq("기존 내용")
      end
    end

    context "한글 파일명 (NFC 정규화)" do
      it "NFD 입력을 NFC로 정규화하여 저장한다" do
        nfc_name = "회고.md"
        nfd_name = nfc_name.unicode_normalize(:nfd)
        expect(nfd_name).not_to eq(nfc_name) # sanity: NFD ≠ NFC byte-wise

        result = writer.atomic_write(tmpdir.join(nfd_name), "내용")

        expect(result.basename.to_s).to eq(nfc_name)
        expect(result.basename.to_s.unicode_normalize(:nfc)).to eq(result.basename.to_s)
        expect(read_utf8(result)).to eq("내용")
      end

      it "NFC 입력은 그대로 NFC로 유지된다 (idempotent)" do
        nfc_name = "수업메모.md"
        result = writer.atomic_write(tmpdir.join(nfc_name), "내용")
        expect(result.basename.to_s).to eq(nfc_name)
      end

      it "ASCII 파일명은 영향을 받지 않는다" do
        result = writer.atomic_write(tmpdir.join("plain.md"), "x")
        expect(result.basename.to_s).to eq("plain.md")
      end
    end
  end
end
