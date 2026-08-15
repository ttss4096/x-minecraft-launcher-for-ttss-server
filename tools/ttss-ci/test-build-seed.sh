#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
builder=${TTSS_BUILD_SEED_SCRIPT:-$script_dir/build-seed-from-export.sh}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
base="$work/base"
export_root="$work/export"
mkdir -p "$base/mods" "$base/resourcepacks" "$export_root/host/main/mods" "$export_root/host/main/config"
printf 'old\n' > "$base/mods/old.jar"
printf 'stale\n' > "$base/mods/stale.jar"
printf 'old-pack\n' > "$base/resourcepacks/old.zip"
for name in hailwall_1.0.3-versionlock.1_neoforge_1.21.1.jar sablecollisiondamage-1.0.8.jar ttss-exclusive-client-neoforge-1.21.1-1.0.0.jar automodpack-old.jar; do
  printf 'base-%s\n' "$name" > "$base/mods/$name"
done
for name in hailwall_1.0.3-versionlock.1_neoforge_1.21.1.jar sablecollisiondamage-1.0.8.jar ttss-exclusive-client-neoforge-1.21.1-1.0.0.jar new.jar; do
  printf 'host-%s\n' "$name" > "$export_root/host/main/mods/$name"
done
printf 'host-config\n' > "$export_root/host/main/config/new.toml"

manifest_list='[]'
while IFS= read -r relative; do
  file="$export_root/host/main/$relative"
  sha=$(sha1sum "$file" | cut -d' ' -f1)
  size=$(stat -c %s "$file")
  manifest_list=$(jq -c --arg file "/$relative" --arg sha "$sha" --arg size "$size" '. + [{file: $file, size: $size, type: "mod", editable: false, forceCopy: false, sha1: $sha, murmur: "1"}]' <<< "$manifest_list")
done < <(find "$export_root/host/main" -type f -printf '%P\n' | sort)
jq -n --argjson list "$manifest_list" '{automodpackVersion: "4.0.6", mcVersion: "1.21.1", loader: "neoforge", loaderVersion: "21.1.236", modpackName: "fixture", list: $list, nonModpackFilesToDelete: [{file: "/mods/stale.jar", sha1: "0123456789abcdef0123456789abcdef01234567", timestamp: "1786700000000"}]}' > "$export_root/host/automodpack-content.json"

(cd "$base" && zip -q -0 -X "$work/base.zip" -r .)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/key.pem" 2>/dev/null
openssl rsa -in "$work/key.pem" -pubout -out "$work/public.pem" 2>/dev/null
mkdir -p "$work/out1" "$work/out2"
env BASE_SEED="$work/base.zip" EXPORT_ROOT="$export_root" AUTOMODPACK_JAR="$base/mods/automodpack-old.jar" OUTPUT_DIR="$work/out1" SIGNING_KEY="$work/key.pem" PUBLIC_KEY="$work/public.pem" "$builder" > "$work/build1.log"
env BASE_SEED="$work/base.zip" EXPORT_ROOT="$export_root" AUTOMODPACK_JAR="$base/mods/automodpack-old.jar" OUTPUT_DIR="$work/out2" SIGNING_KEY="$work/key.pem" PUBLIC_KEY="$work/public.pem" "$builder" > "$work/build2.log"
cmp "$work/out1/ttss-client-seed.zip" "$work/out2/ttss-client-seed.zip"
cmp "$work/out1/ttss-client-seed.manifest.json" "$work/out2/ttss-client-seed.manifest.json"
unzip -Z1 "$work/out1/ttss-client-seed.zip" | grep -Fx 'mods/stale.jar' && exit 1 || true
unzip -Z1 "$work/out1/ttss-client-seed.zip" | grep -Fx 'mods/automodpack-mc1.21.1-neoforge-4.0.6-ttss-managed.2.jar' >/dev/null
unzip -p "$work/out1/ttss-client-seed.zip" 'config/new.toml' | grep -Fx 'host-config' >/dev/null
openssl dgst -sha256 -verify "$work/out1/ttss-client-seed.public.pem" -signature "$work/out1/ttss-client-seed.manifest.sig" "$work/out1/ttss-client-seed.manifest.json" >/dev/null
printf 'build_seed_tests=PASS deterministic=PASS deletion=PASS overlay=PASS signature=PASS\n'
