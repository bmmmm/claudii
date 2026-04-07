class Claudii < Formula
  desc "Fast Claude Code aliases with live model status and session insights ♥"
  homepage "https://github.com/bmmmm/claudii"
  url "https://github.com/bmmmm/claudii/archive/refs/tags/v0.14.0.tar.gz"
  sha256 "9b3b0db4b8e14a2439d225026a345acb2f93c40c8748d5af19213ff5da3eb6e6"
  license "GPL-3.0-only"
  version "0.14.0"

  head "https://github.com/bmmmm/claudii.git", branch: "main"

  depends_on "jq"

  def install
    # Install plugin + all runtime files into libexec
    # claudii.plugin.zsh uses ${0:A:h} to find lib/, config/ — must stay co-located
    libexec.install "claudii.plugin.zsh", "bin", "lib", "config"
    libexec.install "completions" if (buildpath/"completions").exist?

    # Man page
    man1.install "man/man1/claudii.1"

    # Create bin wrappers that set CLAUDII_HOME before calling the real scripts.
    # Homebrew symlinks bins into $(brew --prefix)/bin — write_env_script handles
    # the indirection so CLAUDII_HOME always resolves to libexec, not the symlink dir.
    %w[claudii claudii-status claudii-sessionline].each do |b|
      (bin/b).write_env_script libexec/"bin"/b, CLAUDII_HOME: libexec
    end

    # Register zsh completions with Homebrew
    zsh_completion.install libexec/"completions/_claudii" if (libexec/"completions/_claudii").exist?

  end

  def caveats
    <<~EOS
      Add to your ~/.zshrc:
        source "#{opt_libexec}/claudii.plugin.zsh"

      Then restart your shell or run:
        source ~/.zshrc

      Optional — activate the CC-Statusline:
        claudii cc-statusline on
    EOS
  end

  test do
    assert_match "claudii v#{version}", shell_output("#{bin}/claudii version")
    output = shell_output("#{bin}/claudii config get statusline.models")
    assert_match "opus,sonnet,haiku", output
  end
end
