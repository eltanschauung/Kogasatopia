#!/usr/bin/env bash
set -euo pipefail

# Build an isolated stable TF2Tools derivative. Never installs live files.
if [[ $# != 4 ]]; then
    echo "Usage: $0 SOURCEMOD_CACHE HL2SDK_ROOT METAMOD_SOURCE NEW_BUILD_DIRECTORY" >&2
    exit 2
fi
package_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_cache=$(realpath -e -- "$1")
sdk_root=$(realpath -e -- "$2")
mms_source=$(realpath -e -- "$3")
build_root=$(realpath -m -- "$4")
base=03865e00cc124221122ae9798ad38998566f9a2b
sdk_commit=42ab8953ee32ebeb1348485cb77bc98c81ed09b7
mms_commit=10952328de32065685c72611afcd60e9c415c586

[[ ! -e "$build_root" && ! -L "$build_root" ]] || {
    echo 'Build directory must be new; no existing files will be overwritten.' >&2
    exit 1
}
git -C "$source_cache" cat-file -e "$base^{commit}"
[[ $(git -C "$sdk_root/hl2sdk-tf2" rev-parse HEAD) == "$sdk_commit" ]]
[[ $(git -C "$mms_source" rev-parse HEAD) == "$mms_commit" ]]
[[ -z $(git -C "$sdk_root/hl2sdk-tf2" status --porcelain) ]]
[[ -z $(git -C "$mms_source" status --porcelain) ]]
mkdir -m 700 -- "$build_root"
git clone --shared --no-checkout -- "$source_cache" "$build_root/source"
git -C "$build_root/source" checkout --detach "$base"
git -C "$build_root/source" submodule update --init --recursive
cp -- "$package_dir"/overlay/extensions/tf2/* "$build_root/source/extensions/tf2/"
mkdir -- "$build_root/build"
(
    cd -- "$build_root/build"
    # Clang 19 renamed one SDK warning flag. Suppress only the unknown-warning
    # diagnostic, keeping the other upstream warnings-as-errors checks intact.
    CXXFLAGS="${CXXFLAGS:-} -Wno-error=unknown-warning-option" nice -n 10 \
        python3 ../source/configure.py --sdks tf2 --targets x86 \
        --enable-optimize --enable-debug --no-mysql \
        --hl2sdk-root "$sdk_root" --mms-path "$mms_source"
    nice -n 10 python3 "$package_dir/build_tf2tools_only.py" "$build_root/build"
)
binary="$build_root/build/extensions/tf2/game.tf2.ext.2.tf2/linux-x86/game.tf2.ext.2.tf2.so"
test -s "$binary"
sha256sum -- "$binary"
echo 'Built TF2Tools only. Deployment requires a separately validated server restart.'
