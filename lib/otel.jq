# otel.jq — OTEL sample rows → the perf-cache shape (`claudii-otel build`).
#
# Input (via `jq -n -L lib -f`): NDJSON rows from lib/otel-extract.jq.
# Args:
#   $repomap   [{sessionId: repo}] from claudii-otel `_repomap` (repo-map log or caches),
#              via --slurpfile (hence the [0]) — too big for an argument
#   $floor     "YYYY-MM-DD"        inclusive day cutoff (window lower bound)
# The shaping itself lives in lib/otel_doc.jq, shared with the fused
# `build --render` modes.
include "otel_doc";

otel_doc($repomap[0]; $floor)
