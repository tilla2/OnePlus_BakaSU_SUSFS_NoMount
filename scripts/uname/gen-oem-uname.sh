#!/usr/bin/env bash
# gen-oem-uname.sh — OEM-like kernel release suffix (LOCALVERSION) generator.
#
# Usage:
#   scripts/uname/gen-oem-uname.sh --kernel-version <x.y[.z]> --kmi <androidXX-x.y> [--format <fmt>] [--seed <string>]
#
# Prints ONLY the suffix on stdout; diagnostics go to stderr. Exits non-zero on any failure.
# Last tier of the uname chain: dispatch override > genuine config uname > this generator.
# With --seed every random component is derived from sha256(seed), so re-runs reproduce the value.
#
# ── Calibration data ──────────────────────────────────────────────────────────────────────────
# Audited from all 70 configs of Bouteillepleine/OnePlus-BakaSu_NMS @ NoMount (c0455201), every
# one of which carries a genuine uname. Extend by adding rows to KMI_FORMAT / KMI_GEN / KMI_TAIL.
#
# | KMI            | default fmt | gen  | tail | corpus (n=70)                                          |
# |----------------|-------------|------|------|--------------------------------------------------------|
# | android16-6.12 | oplus-ab    | 5|6  | -4k  | 9: gen5 x4 + gen6 x4 plain ab, 1 MTK o-format outlier  |
# | android15-6.6  | oplus-ab    | 8    | -4k  | 18: all gen 8; 8 plain ab, 10 abogki (per model)       |
# | android14-6.1  | oplus-o     | 11   | none | 26: all "11-o-g<12hex>"                                |
# | android13-5.15 | oplus-o-bld | 8    | none | 11: "8-o-<bld 01144..01179>-g<12hex>"                  |
# | android12-5.10 | oplus-o     | 9    | none | 6: all "9-o-g<12hex>"                                  |
#
# Number ranges (corpus min..max): ab 14519050..15898589 (8 digits), abogki 446052083..500782043
# (9 digits), bld 01144..01179 (5 digits). The generator samples slightly widened windows.
#
# Format templates:
#   oplus-ab       <gen>-g<12hex>-ab<8 digits>[-4k]       5-gb2a876903b49-ab14541642-4k
#   oplus-abogki   <gen>-g<12hex>-abogki<9 digits>[-4k]   8-g7e1f3c083cc6-abogki467167594-4k
#   oplus-o        <gen>-o-g<12hex>                       11-o-gac2e718ebee6
#   oplus-o-bld    <gen>-o-<5-digit bld>-g<12hex>         8-o-01178-ge9806715b271
#   xiaomi-abogki  <gen>-g<12hex>-abogki<9 digits>-4k     5-g16e473de48a3-abogki462654244-4k
# ──────────────────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

declare -A KMI_FORMAT=(
  [android16-6.12]=oplus-ab
  [android15-6.6]=oplus-ab
  [android14-6.1]=oplus-o
  [android13-5.15]=oplus-o-bld
  [android12-5.10]=oplus-o
)
# Space-separated attested gen digits; more than one = deterministic pick from the seed.
declare -A KMI_GEN=(
  [android16-6.12]="5 6"
  [android15-6.6]="8"
  [android14-6.1]="11"
  [android13-5.15]="8"
  [android12-5.10]="9"
)
declare -A KMI_TAIL=(
  [android16-6.12]="-4k"
  [android15-6.6]="-4k"
  [android14-6.1]=""
  [android13-5.15]=""
  [android12-5.10]=""
)
MAX_LEN=44

die() { echo "❌ gen-oem-uname: $*" >&2; exit 1; }

KVER="" KMI="" FMT="" SEED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kernel-version) KVER="${2:-}"; shift 2 ;;
    --kmi)            KMI="${2:-}"; shift 2 ;;
    --format)         FMT="${2:-}"; shift 2 ;;
    --seed)           SEED="${2:-}"; shift 2 ;;
    -h|--help)        sed -n '2,8p' "$0" >&2; exit 0 ;;
    *)                die "unknown argument: $1" ;;
  esac
done

[ -n "$KMI" ] || die "--kmi is required (e.g. android16-6.12)"
[ -n "$KVER" ] || die "--kernel-version is required (e.g. 6.12.23)"
[[ "$KVER" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "invalid --kernel-version '$KVER'"
[ -n "${KMI_FORMAT[$KMI]+x}" ] || die "no calibration for KMI '$KMI' (known: ${!KMI_FORMAT[*]})"
kmi_base="${KMI#*-}"
kver_base="$(cut -d. -f1-2 <<<"$KVER")"
[ "$kver_base" = "$kmi_base" ] || die "kernel version $KVER does not belong to KMI $KMI"

FMT="${FMT:-${KMI_FORMAT[$KMI]}}"
TAIL="${KMI_TAIL[$KMI]}"
case "$FMT" in
  oplus-ab|oplus-abogki|oplus-o|oplus-o-bld) ;;
  xiaomi-abogki) TAIL="-4k" ;;
  *) die "unknown --format '$FMT'" ;;
esac

# ── Entropy: seeded (sha256 chain) or /dev/urandom ──
POOL="" CTR=0
next_hex() { # $1 = number of hex chars to return
  local need="$1"
  while [ "${#POOL}" -lt "$need" ]; do
    if [ -n "$SEED" ]; then
      POOL+="$(printf '%s|%d' "$SEED" "$CTR" | sha256sum | cut -c1-64)"
      CTR=$((CTR + 1))
    else
      POOL+="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
    fi
  done
  printf '%s' "${POOL:0:$need}"
  POOL="${POOL:$need}"
}
rand_range() { # inclusive integer in [$1, $2]
  local lo="$1" hi="$2" r
  r=$((16#$(next_hex 12)))
  echo $(( lo + r % (hi - lo + 1) ))
}

read -r -a gens <<<"${KMI_GEN[$KMI]}"
if [ "${#gens[@]}" -gt 1 ] && [ -n "$SEED" ]; then
  GEN="${gens[$(rand_range 0 $(( ${#gens[@]} - 1 )))]}"
else
  GEN="${gens[0]}"
fi

GHASH="$(next_hex 12)"
case "$FMT" in
  oplus-ab)               OUT="${GEN}-g${GHASH}-ab$(rand_range 14400000 15999999)${TAIL}" ;;
  oplus-abogki|xiaomi-abogki)
                          OUT="${GEN}-g${GHASH}-abogki$(rand_range 440000000 509999999)${TAIL}" ;;
  oplus-o)                OUT="${GEN}-o-g${GHASH}" ;;
  oplus-o-bld)            OUT="${GEN}-o-$(printf '%05d' "$(rand_range 1140 1185)")-g${GHASH}" ;;
esac

[[ "$OUT" =~ ^[A-Za-z0-9._+-]+$ ]] || die "generated value has invalid characters: $OUT"
[ "${#OUT}" -le "$MAX_LEN" ] || die "generated value exceeds $MAX_LEN chars: $OUT"
echo "gen-oem-uname: $KMI/$KVER fmt=$FMT gen=$GEN seeded=$([ -n "$SEED" ] && echo yes || echo no)" >&2
printf '%s\n' "$OUT"
