#!/bin/bash

# Compiles the QML shaders in common/shaders/ to the .qsb files Qt Quick
# loads. The .qsb files are checked in, so neither users nor the plugin
# ever need the compiler; only a change to a shader does.
#
#   scripts/shaders.sh          compile every shader
#   scripts/shaders.sh --check  fail if a checked-in .qsb is out of date
#
# Needs qsb from qt6-shadertools (`pacman -S qt6-shadertools`).

set -eo pipefail
cd "$(dirname "$0")/.." || exit 1

qsb=$(command -v qsb || true)
[[ -n $qsb ]] || qsb=/usr/lib/qt6/bin/qsb
if [[ ! -x $qsb ]]; then
  echo "shaders: qsb not found; install qt6-shadertools" >&2
  exit 2
fi

check=false
[[ ${1:-} == --check ]] && check=true

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

failed=0
for source in common/shaders/*.frag common/shaders/*.vert; do
  [[ -e $source ]] || continue
  out="$source.qsb"
  # The GLSL versions Qt Quick's OpenGL backend picks from, plus Vulkan's SPIR-V.
  "$qsb" --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$scratch/out.qsb" "$source"
  if $check; then
    if ! cmp -s "$scratch/out.qsb" "$out"; then
      echo "shaders: $out is out of date; run scripts/shaders.sh" >&2
      failed=1
    fi
  else
    cp "$scratch/out.qsb" "$out"
    echo "shaders: $out"
  fi
done
exit $failed
