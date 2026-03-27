# test_install.sh — install/uninstall E2E tests (uses isolated temp dirs)

TEST_TMP="$CLAUDII_HOME/tmp/test_install"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/config/claudii"
touch "$TEST_TMP/zshrc"

export CLAUDII_INSTALL_BIN_DIR="$TEST_TMP/bin"
export CLAUDII_INSTALL_ZSHRC="$TEST_TMP/zshrc"
export CLAUDII_INSTALL_CONFIG_DIR="$TEST_TMP/config/claudii"

# ── install ──

bash "$CLAUDII_HOME/install.sh" >/dev/null 2>&1

# binaries linked
for bin in claudii claudii-status claudii-sessionline; do
  if [[ -L "$TEST_TMP/bin/$bin" ]]; then
    assert_eq "install: $bin symlinked" "true" "true"
  else
    assert_eq "install: $bin symlinked" "symlink" "missing"
  fi
done

# symlinks point to correct source
for bin in claudii claudii-status claudii-sessionline; do
  target=$(readlink "$TEST_TMP/bin/$bin" 2>/dev/null || true)
  assert_eq "install: $bin → $CLAUDII_HOME/bin/$bin" "$CLAUDII_HOME/bin/$bin" "$target"
done

# source line added to zshrc
zshrc=$(cat "$TEST_TMP/zshrc")
assert_contains "install: source line in zshrc" "claudii.plugin.zsh" "$zshrc"

# config created from defaults
assert_file_exists "install: config.json created" "$TEST_TMP/config/claudii/config.json"
models=$(jq -r '.statusline.models' "$TEST_TMP/config/claudii/config.json")
assert_eq "install: config has default models" "opus,sonnet,haiku" "$models"

# ── idempotent: run install again ──

bash "$CLAUDII_HOME/install.sh" >/dev/null 2>&1

# no duplicate source lines
count=$(grep -c "claudii.plugin.zsh" "$TEST_TMP/zshrc" || true)
assert_eq "install: idempotent — no duplicate source lines" "1" "$count"

# ── uninstall (without --purge) ──

bash "$CLAUDII_HOME/uninstall.sh" >/dev/null 2>&1

# symlinks removed
for bin in claudii claudii-status claudii-sessionline; do
  if [[ ! -e "$TEST_TMP/bin/$bin" ]]; then
    assert_eq "uninstall: $bin removed" "true" "true"
  else
    assert_eq "uninstall: $bin removed" "removed" "still exists"
  fi
done

# source line removed from zshrc
zshrc=$(cat "$TEST_TMP/zshrc")
if echo "$zshrc" | grep -q "claudii.plugin.zsh"; then
  assert_eq "uninstall: source line removed" "removed" "still present"
else
  assert_eq "uninstall: source line removed" "true" "true"
fi

# config kept (no --purge)
assert_file_exists "uninstall: config kept without --purge" "$TEST_TMP/config/claudii/config.json"

# ── uninstall --purge ──

bash "$CLAUDII_HOME/install.sh" >/dev/null 2>&1
bash "$CLAUDII_HOME/uninstall.sh" --purge >/dev/null 2>&1

if [[ ! -d "$TEST_TMP/config/claudii" ]]; then
  assert_eq "uninstall --purge: config removed" "true" "true"
else
  assert_eq "uninstall --purge: config removed" "removed" "still exists"
fi

# Cleanup
rm -rf "$TEST_TMP"
unset CLAUDII_INSTALL_BIN_DIR CLAUDII_INSTALL_ZSHRC CLAUDII_INSTALL_CONFIG_DIR
