# claudii — Session-Übergabe

## Stand: v0.1.0 (2026-03-27)

### Was ist claudii?
zsh-Plugin + CLI für Claude Code Power-User. Zwei Ebenen:
- **RPROMPT** (außerhalb Claude): Model-Health via RSS + Last-Fetch-Age
- **In-Session Statusline** (innerhalb Claude): Context %, Cost, Tokens, Rate Limits

### Was wurde gebaut
- 59/59 E2E Tests grün
- Config-System (`~/.config/claudii/config.json`) — alles konfigurierbar
- RSS-Parser mit per-model Status + Recovery-Erkennung
- Auto-Fallback (Opus down → Sonnet, etc.)
- `claudii-sessionline` für Claude's native statusLine
- Shell-Funktionen: `cl`, `clo`, `clm`, `clq`, `clh`

### Was noch nicht getestet
- `claudii install-sessionline` — manuell ausführen, dann Claude neustarten
- RPROMPT im neuen Terminal verifizieren (alte Session hatte gestackte Hooks)
- `claudii-sessionline` live in einer Claude-Session

### Nächste Schritte
1. **Neues Terminal öffnen**, `clh` testen, RPROMPT prüfen
2. `claudii install-sessionline` ausführen, Claude neustarten, Sessionline prüfen
3. Workspace-Farbe für claudii vergeben (VS Code + Ghostty)
4. Auf GitHub pushen wenn stabil

### Offene TODOs (~/doku/TODO.md)
- Account-Usage & Limits (wartet auf Anthropic CLI-API)
- Interaktives TUI-Menü für `claudii config`
- Token-Usage in RPROMPT
- Prometheus textfile collector auf garage
- Claude Code Plugin-Integration (`claude plugin`)

### Bekannte Eigenheiten
- `jq -e` gibt Exit 1 für `false` — deshalb `type != "null"` Pattern im config_get
- zsh splittet IFS anders als bash — `${(s:,:)var}` statt `IFS=','`
- RSS-Feed: Recovery steht in HTML-encoded Description, nicht im Titel
- statusLine JSON: `rate_limits` erst nach erstem API-Response verfügbar

### Dateien
```
~/offline_coding/claudii/          # Repo (git init, kein Remote)
~/offline_coding/dotfiles/zshrc    # source claudii.plugin.zsh
~/.config/claudii/config.json      # User-Config
~/doku/TODO.md                     # Offene Punkte
~/doku/claude-code.md              # Doku (verweist auf claudii)
```
