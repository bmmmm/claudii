# claudii ♥

Fast Claude Code aliases with live model status and session insights.

## Install

```bash
brew tap bmmmm/tap && brew install claudii
```

Add to `~/.zshrc`:
```bash
source "$(brew --prefix)/opt/claudii/libexec/claudii.plugin.zsh"
```

<details>
<summary>Manual install (without Homebrew)</summary>

```bash
git clone https://github.com/bmmmm/claudii ~/claudii
bash ~/claudii/install.sh
```
</details>

## What you get

**Aliases** — fast access to Claude Code:
```bash
cl                    # Sonnet high
clo                   # Opus high
clm                   # Opus max
clq                   # search mode
clh                   # alias table + live status
```

**ClaudeStatus** — model health right in your prompt:
```
➜  project (main)                        [Opus ↓ Sonnet ✓ Haiku ✓] 3m ⟳
```

**Claude Code Status Line** — context, cost, tokens inside Claude:
```
Opus ████░░░░░░ 42% $0.55 in:15.2K out:4.5K 5h:23% 7d:71%
```

## Quick start

```bash
claudii                       # show all commands
claudii status                # live model health
claudii sessionline on        # enable Claude Code Status Line
man claudii                   # full reference
```

## Requirements

`zsh` · `jq` · `curl`

## Credits

Claude Code Status Line by [wynandw87/claude-code-statusline](https://github.com/wynandw87/claude-code-statusline).

## License

[GPL-3.0](LICENSE)
