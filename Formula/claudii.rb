class Claudii < Formula
  desc "Claude Interaction Intelligence — zsh plugin + CLI for Claude Code"
  homepage "https://github.com/bmmmm/claudii"
  url "https://github.com/bmmmm/claudii/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256" # update with: brew fetch --build-from-source Formula/claudii.rb
  license "GPL-3.0-only"
  version "0.1.0"

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

    # Note: vendor/claude-code-statusline (git submodule) is not included in the
    # Homebrew tarball. bin/claudii-sessionline falls back to its built-in
    # implementation automatically. Users can clone the submodule manually:
    #   git clone https://github.com/wynandw87/claude-code-statusline \
    #     "$(brew --prefix claudii)/libexec/vendor/claude-code-statusline"
  end

  def caveats
    <<~EOS
      Add to your ~/.zshrc:
        source "#{opt_libexec}/claudii.plugin.zsh"

      Then restart your shell or run:
        source ~/.zshrc

      Optional — activate the Claude Code Status Line:
        claudii sessionline on
    EOS
  end

  test do
    assert_match "claudii v#{version}", shell_output("#{bin}/claudii version")
    output = shell_output("#{bin}/claudii config get statusline.models")
    assert_match "opus,sonnet,haiku", output
  end
end
