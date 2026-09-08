class PspWallpaper < Formula
  desc "PSP-style animated wave live wallpaper for macOS, drawn on the GPU with Metal"
  homepage "https://github.com/qazaqninja/psp-wallpaper"
  url "https://github.com/qazaqninja/psp-wallpaper/releases/download/v1.1.1/psp-wallpaper-1.1.1-arm64.tar.gz"
  sha256 "e5ef709a8520084ddbefa3e3bb2ae1e853f20f05ef698db18536362777b764bd"
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

      Settings and presets live behind the wave icon in the menu bar.
      Or from the shell:  psp-wallpaper --preset Aurora
      Config:  ~/.config/psp-wallpaper/config.json (hot-reloads on save)
      Presets: ~/.config/psp-wallpaper/presets/
    EOS
  end

  test do
    system bin/"psp-wallpaper", "--selftest"
  end
end
