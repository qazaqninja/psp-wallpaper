class PspWallpaper < Formula
  desc "PSP-style animated wave live wallpaper for macOS, drawn on the GPU with Metal"
  homepage "https://github.com/qazaqninja/psp-wallpaper"
  url "https://github.com/qazaqninja/psp-wallpaper/releases/download/v1.0.0/psp-wallpaper-1.0.0-arm64.tar.gz"
  sha256 "5001488d9700e6a26d7c1bf7380c826b5f1ef99e0fa19e7fb24f4563a26d5346"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64 # Intel: build from source, see README

  def install
    bin.install "PSPWallpaper" => "psp-wallpaper"
  end

  service do
    run [opt_bin/"psp-wallpaper"]
    keep_alive true
    log_path var/"log/psp-wallpaper.log"
    error_log_path var/"log/psp-wallpaper.log"
  end

  def caveats
    <<~EOS
      Start it now and at every login:
        brew services start psp-wallpaper

      Settings live behind the wave icon in the menu bar.
      Config file: ~/.config/psp-wallpaper/config.json (hot-reloads on save)
    EOS
  end

  test do
    system bin/"psp-wallpaper", "--selftest"
  end
end
