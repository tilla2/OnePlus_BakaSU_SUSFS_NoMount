#!/usr/bin/env bash
# Unit test for gen-oem-uname.sh: 20 runs per KMI against the per-KMI regexes, seed reproducibility,
# length cap and rejection of bad input. Exits non-zero on the first failure.
set -euo pipefail
GEN="$(dirname "$0")/gen-oem-uname.sh"
fail() { echo "❌ $*"; exit 1; }

check() { # kmi kver regex [format]
  local kmi="$1" kver="$2" re="$3" fmt="${4:-}" i out
  for i in $(seq 1 20); do
    out="$("$GEN" --kmi "$kmi" --kernel-version "$kver" ${fmt:+--format "$fmt"} 2>/dev/null)"
    [[ "$out" =~ $re ]] || fail "$kmi ${fmt:-default} run $i: '$out' !~ $re"
    [ "${#out}" -le 44 ] || fail "$kmi: '$out' longer than 44"
  done
  echo "✅ $kmi ${fmt:-default}: 20/20 match $re (last: $out)"
}

check android14-6.1  6.1.118  '^11-o-g[0-9a-f]{12}$'
check android15-6.6  6.6.30   '^8-g[0-9a-f]{12}-ab[0-9]{8}-4k$'
check android15-6.6  6.6.89   '^8-g[0-9a-f]{12}-abogki[0-9]{9}-4k$' oplus-abogki
check android16-6.12 6.12.23  '^[56]-g[0-9a-f]{12}-ab[0-9]{8}-4k$'
check android13-5.15 5.15.167 '^8-o-[0-9]{5}-g[0-9a-f]{12}$'
check android12-5.10 5.10.209 '^9-o-g[0-9a-f]{12}$'

# Seeded runs reproduce; different seeds differ; both 6.12 gen digits are reachable via the seed.
a="$("$GEN" --kmi android16-6.12 --kernel-version 6.12.23 --seed run1 2>/dev/null)"
b="$("$GEN" --kmi android16-6.12 --kernel-version 6.12.23 --seed run1 2>/dev/null)"
c="$("$GEN" --kmi android16-6.12 --kernel-version 6.12.23 --seed run2 2>/dev/null)"
[ "$a" = "$b" ] || fail "seed not reproducible: $a vs $b"
[ "$a" != "$c" ] || fail "different seeds produced the same value"
gens="$(for s in $(seq 1 40); do "$GEN" --kmi android16-6.12 --kernel-version 6.12.23 --seed "s$s" 2>/dev/null | cut -d- -f1; done | sort -u | tr '\n' ' ')"
[ "$gens" = "5 6 " ] || fail "seeded 6.12 gen digits should cover {5,6}, got: $gens"
echo "✅ seed reproducible ($a), distinct per seed, 6.12 gen digits seen: $gens"

# Unseeded 6.12 defaults to gen 5 (OP15 GA family).
[ "$("$GEN" --kmi android16-6.12 --kernel-version 6.12.58 2>/dev/null | cut -d- -f1)" = 5 ] || fail "unseeded 6.12 gen != 5"
echo "✅ unseeded 6.12 gen digit = 5"

# Bad input must fail.
for args in "--kmi android16-6.12 --kernel-version 6.6.30" "--kmi android99-9.9 --kernel-version 9.9.1" \
            "--kmi android16-6.12" "--kmi android15-6.6 --kernel-version 6.6.30 --format bogus"; do
  # shellcheck disable=SC2086
  if "$GEN" $args >/dev/null 2>&1; then fail "accepted bad input: $args"; fi
done
echo "✅ bad input rejected (KMI/version mismatch, unknown KMI, missing version, unknown format)"
echo "✅ gen-oem-uname.sh: all tests passed"
