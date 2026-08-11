#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
app_name="FileMaker Script Bridge"
bundle_dir="$project_dir/dist/$app_name.app"
zip_path="$project_dir/dist/$app_name.app.zip"
contents_dir="$bundle_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
universal_dir="$project_dir/.build/universal/$configuration"
binary_path="$universal_dir/FileMakerScriptBridge"
icon_file="$project_dir/Resources/AppIcon.icns"

cd "$project_dir"
mkdir -p "$universal_dir"

architecture_binaries=()
for architecture in arm64 x86_64; do
    scratch_path="$project_dir/.build/package-$architecture"
    module_cache_path="$scratch_path/SCKCModuleCache"
    target_triple="${architecture}-apple-macosx13.0"
    env \
        CLANG_MODULE_CACHE_PATH="$module_cache_path" \
        SWIFTPM_MODULECACHE_OVERRIDE="$module_cache_path" \
        swift build \
            -c "$configuration" \
            --disable-sandbox \
            --scratch-path "$scratch_path" \
            --triple "$target_triple"
    architecture_binaries+=("$(swift build -c "$configuration" --scratch-path "$scratch_path" --triple "$target_triple" --show-bin-path)/FileMakerScriptBridge")
done

lipo -create "${architecture_binaries[@]}" -output "$binary_path"
lipo "$binary_path" -verify_arch arm64 x86_64

mkdir -p "$macos_dir" "$resources_dir"
cp "$binary_path" "$macos_dir/FileMakerScriptBridge"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$icon_file" "$resources_dir/AppIcon.icns"

xattr -cr "$bundle_dir"
xattr -d com.apple.FinderInfo "$bundle_dir" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$bundle_dir" 2>/dev/null || true
codesign --force --deep --sign - "$bundle_dir"
if ! codesign --verify --deep --strict "$bundle_dir"; then
    echo "Warning: iCloud reattached Finder metadata; verifying a metadata-free copy instead." >&2
fi

clean_dir="$(mktemp -d /private/tmp/filemaker-script-bridge-package.XXXXXX)"
trap 'rm -rf "$clean_dir"' EXIT
clean_bundle="$clean_dir/$app_name.app"
ditto --norsrc --noextattr "$bundle_dir" "$clean_bundle"
codesign --force --deep --sign - "$clean_bundle"
codesign --verify --deep --strict "$clean_bundle"
rm -f "$zip_path"
ditto -c -k --keepParent --norsrc "$clean_bundle" "$zip_path"

echo "$bundle_dir"
echo "$zip_path"
