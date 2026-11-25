# touches: install.sh uninstall.sh bin/claudii lib/cmd/system.sh
# test_install.sh — install/uninstall E2E tests (uses isolated temp dirs)

TEST_TMP="$CLAUDII_TEST_TMP/test_install"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/config/claudii"
touch "$TEST_TMP/zshrc"

export CLAUDII_INSTALL_BIN_DIR="$TEST_TMP/bin"
export CLAUDII_INSTALL_ZSHRC="$TEST_TMP/zshrc"
export CLAUDII_INSTALL_CONFIG_DIR="$TEST_TMP/config/claudii"

# install.sh refuses to run next to a Homebrew install of itself (`brew --prefix`). A
# developer machine with the formula installed must not turn this test red, so
# `brew` is stubbed out for the install runs below.
mkdir -p "$TEST_TMP/nobrew"
printf '#!/bin/sh\nexit 1\n' > "$TEST_TMP/nobrew/brew"
chmod +x "$TEST_TMP/nobrew/brew"
_inst_path="$PATH"
export PATH="$TEST_TMP/nobrew:$PATH"

# ── install ──

bash "$CLAUDII_HOME/install.sh" >/dev/null 2>&1

# binaries linked
for bin in claudii claudii-status claudii-cc-statusline claudii-insights; do
  if [[ -L "$TEST_TMP/bin/$bin" ]]; then
    assert_eq "install: $bin symlinked" "true" "true"
  else
    assert_eq "install: $bin symlinked" "symlink" "missing"
  fi
done

# symlinks point to correct source
for bin in claudii claudii-status claudii-cc-statusline claudii-insights; do
  target=$(readlink "$TEST_TMP/bin/$bin" 2>/dev/null || true)
  assert_eq "install: $bin → $CLAUDII_HOME/bin/$bin" "$CLAUDII_HOME/bin/$bin" "$target"
done

# the linked binary runs without CLAUDII_HOME — it used to derive the checkout
# from the link's own directory and die on "<bin dir>/../lib/visual.sh: No such
# file". Also through a relative link to that link (two hops).
_ver=$(sed -nE 's/^VERSION="([^"]+)"$/\1/p' "$CLAUDII_HOME/bin/claudii")
_rc=0
_out=$(cd / && env -u CLAUDII_HOME "$TEST_TMP/bin/claudii" version 2>&1) || _rc=$?
assert_eq "install: linked claudii runs without CLAUDII_HOME (rc)" "0" "$_rc"
assert_contains "install: linked claudii prints its version" "$_ver" "$_out"
mkdir -p "$TEST_TMP/rel"
ln -s ../bin/claudii "$TEST_TMP/rel/claudii"
_rc=0
_out=$(cd / && env -u CLAUDII_HOME "$TEST_TMP/rel/claudii" version 2>&1) || _rc=$?
assert_eq "install: relative link chain resolves (rc)" "0" "$_rc"
assert_contains "install: relative link chain prints its version" "$_ver" "$_out"
unset _ver _rc _out

# source line added to zshrc
zshrc=$(cat "$TEST_TMP/zshrc")
assert_contains "install: source line in zshrc" "claudii.plugin.zsh" "$zshrc"

# config created from defaults
assert_file_exists "install: config.json created" "$TEST_TMP/config/claudii/config.json"
models=$(jq -r '.statusline.models' "$TEST_TMP/config/claudii/config.json")
assert_eq "install: config has default models" "opus,sonnet,haiku,fable" "$models"

# ── idempotent: run install again ──

bash "$CLAUDII_HOME/install.sh" >/dev/null 2>&1

# no duplicate source lines
count=$(grep -c "claudii.plugin.zsh" "$TEST_TMP/zshrc" || true)
assert_eq "install: idempotent — no duplicate source lines" "1" "$count"

# ── uninstall (without --purge) ──

bash "$CLAUDII_HOME/uninstall.sh" >/dev/null 2>&1

# symlinks removed
for bin in claudii claudii-status claudii-cc-statusline claudii-insights; do
  if [[ ! -e "$TEST_TMP/bin/$bin" ]]; then
    assert_eq "uninstall: $bin removed" "true" "true"
  else
    assert_eq "uninstall: $bin removed" "removed" "still exists"
  fi
done

# source line removed from zshrc
zshrc=$(cat "$TEST_TMP/zshrc")
if grep -q "claudii.plugin.zsh" <<< "$zshrc"; then
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
export PATH="$_inst_path"
unset CLAUDII_INSTALL_BIN_DIR CLAUDII_INSTALL_ZSHRC CLAUDII_INSTALL_CONFIG_DIR _inst_path
