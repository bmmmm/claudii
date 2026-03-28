# claudii

**Claude Interaction Intelligence** — zsh plugin + CLI for Claude Code power users.

```
  claudii v0.1.0 — Claude Interaction Intelligence

  ClaudeStatus
    status [on|off|5m|15m|30m]    live model check · RPROMPT on/off · refresh
    show model [add|rm|<names>]    models shown in RPROMPT

  aliases
    cl     sonnet   high    default
    clo    opus     high    complex tasks
    clm    opus     max     max effort
    clq    sonnet   medium  search  (claudii search ['query'])
    clh                     alias table + live status

  Claude Code Status Line  (by wynandw87)
    sessionline [on|off]           context · cost · tokens · rate limits

  tools
    config [get|set|reset|export|import]
    debug  [off|error|warn|info|debug]
    metrics · restart · update · about

  man claudii  full reference
```

## Install

**Homebrew**
```bash
brew tap bmmmm/claudii
brew install claudii
# add to ~/.zshrc:
source "$(brew --prefix)/opt/claudii/libexec/claudii.plugin.zsh"
```

**Manual**
```bash
git clone https://github.com/bmmmm/claudii ~/claudii
bash ~/claudii/install.sh
```

## What it does

```
➜  project (main)                        [Opus ↓ Sonnet ✓ Haiku ✓] 3m ⟳
```

RPROMPT shows model health at a glance. Background refresh, no network in prompt.

**Inside Claude Code** — Claude Code Status Line shows context, cost, tokens:
```
Opus ████░░░░░░ 42% $0.55 in:15.2K out:4.5K 5h:23% 7d:71%
```

## Quick start

```bash
cl                    # launch Claude Sonnet
clo                   # launch Claude Opus
claudii status        # live model health
claudii sessionline on   # enable Claude Code Status Line
man claudii           # full reference
```

## Requirements

`zsh` · `jq` · `curl`

## Credits

Claude Code Status Line by [wynandw87/claude-code-statusline](https://github.com/wynandw87/claude-code-statusline).

## License

[GPL-3.0](LICENSE)
