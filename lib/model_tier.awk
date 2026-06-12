# model_tier.awk — collapse a raw model display name to its tier label.
# Injected (string-interpolated, like epoch_to_date.awk) into the stage-1
# augment passes of `claudii cost` (lib/cmd/cost.sh) and `claudii trends`
# (lib/cmd/display.sh). Single source of truth for the awk-side tier collapse.
#
# Most-capable-first; a name matching no tier is returned unchanged (shows up
# as its own legend entry). Version bumps within a tier need no change here —
# a NEW tier needs a branch here (and see the model-ship checklist in
# CLAUDE.md for the jq/_rates siblings).
function tier_label(m,   l) {
  l = tolower(m)
  if (l ~ /(^|[^a-z])fable([^a-z]|$)/)  return "Fable"
  if (l ~ /(^|[^a-z])opus([^a-z]|$)/)   return "Opus"
  if (l ~ /(^|[^a-z])sonnet([^a-z]|$)/) return "Sonnet"
  if (l ~ /(^|[^a-z])haiku([^a-z]|$)/)  return "Haiku"
  return m
}
