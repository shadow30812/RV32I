#!/usr/bin/env bash

# RV32I regression suite: assembles every tests/programs/*.s with asm.py, runs it on
# tests/tb_regress.v and checks the final state listed in the matching .exp file.
#
# Needs python3, iverilog and vvp; expects the SPI master sources in SPI/src next to RV32I/

#   tests/run_regression.sh [program ...]    run all programs, or only those named
#   RTL_DIR=<dir> tests/run_regression.sh    run against another copy of src/

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RV32I_DIR="$(dirname "$TESTS_DIR")"
SPI_DIR="$(dirname "$RV32I_DIR")/SPI/src"
RTL_DIR="${RTL_DIR:-$RV32I_DIR/src}"
BUILD_DIR="$TESTS_DIR/build"

for tool in python3 iverilog vvp; do
  command -v "$tool" >/dev/null || { echo "error: $tool not found" >&2; exit 2; }
done
[ -d "$SPI_DIR" ] || { echo "error: SPI sources not found at $SPI_DIR" >&2; exit 2; }

mkdir -p "$BUILD_DIR"

echo "Compiling RTL from $RTL_DIR"
if ! iverilog -o "$BUILD_DIR/tb_regress.vvp" -s tb_regress \
    "$RTL_DIR"/*.v "$SPI_DIR"/*.v "$TESTS_DIR/tb_regress.v" > "$BUILD_DIR/compile.log" 2>&1; then
  cat "$BUILD_DIR/compile.log"
  echo "error: compilation failed" >&2
  exit 2
fi

if [ $# -gt 0 ]; then
  programs=("$@")
else
  programs=()
  for s in "$TESTS_DIR"/programs/*.s; do programs+=("$(basename "$s" .s)"); done
fi

pass=0
fail=0
failed=()

for name in "${programs[@]}"; do
  src="$TESTS_DIR/programs/$name.s"
  exp="$TESTS_DIR/programs/$name.exp"
  hex="$BUILD_DIR/$name.hex"
  chk="$BUILD_DIR/$name.chk"
  log="$BUILD_DIR/$name.log"

  if [ ! -f "$src" ] || [ ! -f "$exp" ]; then
    echo "FAIL  $name (missing $name.s or $name.exp)"
    fail=$((fail + 1)); failed+=("$name"); continue
  fi

  if ! python3 "$RV32I_DIR/asm.py" "$src" "$hex" < /dev/null > "$log" 2>&1; then
    echo "FAIL  $name (assembly failed, see $log)"
    fail=$((fail + 1)); failed+=("$name"); continue
  fi

  # .exp -> "<kind> <index> <hex value>" lines read by tb_regress.v
  if ! python3 - "$exp" "$chk" >> "$log" 2>&1 <<'EOF'
import sys
out = []
for n, line in enumerate(open(sys.argv[1]), 1):
    f = line.split("#")[0].split()
    if not f:
        continue
    try:
        if f[0][0] in "xX" and len(f) == 2:
            reg = int(f[0][1:])
            assert 1 <= reg <= 31
            out.append(f"0 {reg} {int(f[1], 0) & 0xFFFFFFFF:08x}")
        elif f[0] == "M" and len(f) == 3:
            addr = int(f[1], 0)
            assert addr % 4 == 0 and addr < 4096
            out.append(f"1 {addr // 4} {int(f[2], 0) & 0xFFFFFFFF:08x}")
        elif f[0] == "B" and len(f) == 2:
            out.append(f"2 0 {int(f[1], 0):08x}")
        else:
            raise ValueError
    except (ValueError, AssertionError):
        sys.exit(f"{sys.argv[1]}:{n}: bad line: {line.strip()}")
open(sys.argv[2], "w").write("\n".join(out) + "\n")
EOF
  then
    echo "FAIL  $name (bad .exp file, see $log)"
    fail=$((fail + 1)); failed+=("$name"); continue
  fi

  vvp -n "$BUILD_DIR/tb_regress.vvp" +hex="$hex" +chk="$chk" >> "$log" 2>&1
  if grep -q "^RESULT: PASS" "$log"; then
    echo "PASS  $name  ($(grep -o '[0-9]* checks.*' "$log"))"
    pass=$((pass + 1))
  else
    echo "FAIL  $name"
    grep -E "^\[FAIL\]|checks," "$log" | sed 's/^/      /'
    fail=$((fail + 1)); failed+=("$name")
  fi
done

echo "-----------------------------------------------------"
echo "$pass passed, $fail failed"
[ $fail -eq 0 ] || { echo "failed: ${failed[*]}"; exit 1; }
