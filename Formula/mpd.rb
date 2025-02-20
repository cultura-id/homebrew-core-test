class Mpd < Formula
  desc "Music Player Daemon"
  homepage "https://www.musicpd.org/"
  url "https://www.musicpd.org/download/mpd/0.23/mpd-0.23.8.tar.xz"
  sha256 "86bb569bf3b519821f36f6bb5564e484e85d2564411b34b200fe2cd3a04e78cf"
  license "GPL-2.0-or-later"
  revision 1
  head "https://github.com/MusicPlayerDaemon/MPD.git", branch: "master"

  livecheck do
    url "https://www.musicpd.org/download.html"
    regex(/href=.*?mpd[._-]v?(\d+(?:\.\d+)+)\.t/i)
  end

  bottle do
    sha256 cellar: :any, arm64_monterey: "50f5c4e6d3d6c9e6e5b06923525524da8b7b640f527534d6d539ebc23135f677"
    sha256 cellar: :any, arm64_big_sur:  "fe909593e6bde1e9bbeb3897dc5c899c4c83e879a9f5dbbd8a772068e008bfd0"
    sha256 cellar: :any, monterey:       "f13dd346b0989fe2de1f162f10622ab0fe1847b10b8261118c04adf664f5a4d8"
    sha256 cellar: :any, big_sur:        "3fe4a01c943a056d5bc7fb4277001f5b45b1a3d32afeb67688f278c8801dac58"
    sha256 cellar: :any, catalina:       "162e0a7f6c42edb65957ee5d28bd7592670f34bf3722e71b38f7f9ed1d46957d"
    sha256               x86_64_linux:   "01199416f22d85c098fa82bff410d5a265f9720808f1b661a3f5061fdcbc4bb6"
  end

  depends_on "boost" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "expat"
  depends_on "faad2"
  depends_on "ffmpeg"
  depends_on "flac"
  depends_on "fluid-synth"
  depends_on "fmt"
  depends_on "glib"
  depends_on "icu4c"
  depends_on "lame"
  depends_on "libao"
  depends_on "libgcrypt"
  depends_on "libid3tag"
  depends_on "libmpdclient"
  depends_on "libnfs"
  depends_on "libsamplerate"
  depends_on "libshout"
  depends_on "libupnp"
  depends_on "libvorbis"
  depends_on macos: :mojave # requires C++17 features unavailable in High Sierra
  depends_on "opus"
  depends_on "sqlite"

  uses_from_macos "curl"

  on_linux do
    depends_on "gcc"
  end

  fails_with gcc: "5"

  # Fix build with FFmpeg 5.1. Backported from
  # https://github.com/MusicPlayerDaemon/MPD/commit/59792cb0b801854ee41be72d33db9542735df754
  patch :DATA

  def install
    # mpd specifies -std=gnu++0x, but clang appears to try to build
    # that against libstdc++ anyway, which won't work.
    # The build is fine with G++.
    ENV.libcxx

    # Replace symbols available only on macOS 12+ with their older versions.
    # https://github.com/MusicPlayerDaemon/MPD/issues/1580
    #
    # This workaround can be removed when the following commit lands in a tagged release (likely 0.23.9):
    # https://github.com/MusicPlayerDaemon/MPD/commit/bbc088ae4ea19767c102ca740765a30b98ffa96b
    if MacOS.version <= :big_sur
      new_syms = ["kAudioObjectPropertyElementMain", "kAudioHardwareServiceDeviceProperty_VirtualMainVolume"]
      # Doing `ENV.append_to_cflags` twice results in line length errors.
      new_syms.each do |new_sym|
        old_sym = new_sym.sub("Main", "Master")
        ENV.append_to_cflags "-D#{new_sym}=#{old_sym}"
      end
    end

    args = %W[
      --sysconfdir=#{etc}
      -Dmad=disabled
      -Dmpcdec=disabled
      -Dsoundcloud=disabled
      -Dao=enabled
      -Dbzip2=enabled
      -Dexpat=enabled
      -Dffmpeg=enabled
      -Dfluidsynth=enabled
      -Dnfs=enabled
      -Dshout=enabled
      -Dupnp=pupnp
      -Dvorbisenc=enabled
    ]

    system "meson", "setup", "output/release", *args, *std_meson_args
    system "meson", "compile", "-C", "output/release"
    ENV.deparallelize # Directories are created in parallel, so let's not do that
    system "meson", "install", "-C", "output/release"

    pkgetc.install "doc/mpdconf.example" => "mpd.conf"
  end

  def caveats
    <<~EOS
      MPD requires a config file to start.
      Please copy it from #{etc}/mpd/mpd.conf into one of these paths:
        - ~/.mpd/mpd.conf
        - ~/.mpdconf
      and tailor it to your needs.
    EOS
  end

  service do
    run [opt_bin/"mpd", "--no-daemon"]
    keep_alive true
    process_type :interactive
    working_dir HOMEBREW_PREFIX
  end

  test do
    # oss_output: Error opening OSS device "/dev/dsp": No such file or directory
    # oss_output: Error opening OSS device "/dev/sound/dsp": No such file or directory
    return if OS.linux? && ENV["HOMEBREW_GITHUB_ACTIONS"]

    require "expect"

    port = free_port

    (testpath/"mpd.conf").write <<~EOS
      bind_to_address "127.0.0.1"
      port "#{port}"
    EOS

    io = IO.popen("#{bin}/mpd --stdout --no-daemon #{testpath}/mpd.conf 2>&1", "r")
    io.expect("output: Successfully detected a osx audio device", 30)

    ohai "Connect to MPD command (localhost:#{port})"
    TCPSocket.open("localhost", port) do |sock|
      assert_match "OK MPD", sock.gets
      ohai "Ping server"
      sock.puts("ping")
      assert_match "OK", sock.gets
      sock.close
    end
  end
end

__END__
diff --git a/src/decoder/plugins/FfmpegIo.cxx b/src/decoder/plugins/FfmpegIo.cxx
index 2e22d9599102ac445fc269c69863f4c2c34bfe1c..5b5c8b40e3a0b95fbf5e75a0cf9b53e2c416a36f 100644
--- a/src/decoder/plugins/FfmpegIo.cxx
+++ b/src/decoder/plugins/FfmpegIo.cxx
@@ -21,10 +21,13 @@
 #define __STDC_CONSTANT_MACROS
 
 #include "FfmpegIo.hxx"
-#include "libavutil/mem.h"
 #include "../DecoderAPI.hxx"
 #include "input/InputStream.hxx"
 
+extern "C" {
+#include <libavutil/mem.h>
+}
+
 AvioStream::~AvioStream()
 {
 	if (io != nullptr) {
