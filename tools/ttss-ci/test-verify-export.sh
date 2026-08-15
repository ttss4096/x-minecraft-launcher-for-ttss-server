#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

make_fixture() {
  local root=$1
  mkdir -p "$root/host/main/mods" "$root/host/main/config" "$root/config"
  printf 'fixture-mod\n' > "$root/host/main/mods/example.jar"
  printf 'fixture-config\n' > "$root/host/main/config/example.toml"

  local mod_sha config_sha mod_size config_size
  mod_sha=$(sha1sum "$root/host/main/mods/example.jar" | cut -d' ' -f1)
  config_sha=$(sha1sum "$root/host/main/config/example.toml" | cut -d' ' -f1)
  mod_size=$(stat -c %s "$root/host/main/mods/example.jar")
  config_size=$(stat -c %s "$root/host/main/config/example.toml")

  jq -n \
    --arg mod_sha "$mod_sha" \
    --arg config_sha "$config_sha" \
    --argjson mod_size "$mod_size" \
    --argjson config_size "$config_size" \
    '{
      automodpackVersion: "4.0.6",
      mcVersion: "1.21.1",
      loader: "neoforge",
      loaderVersion: "21.1.236",
      modpackName: "TTSS fixture",
      list: [
        {file: "/mods/example.jar", size: ($mod_size | tostring), type: "mod", editable: false, forceCopy: false, sha1: $mod_sha, murmur: "1"},
        {file: "/config/example.toml", size: ($config_size | tostring), type: "config", editable: false, forceCopy: false, sha1: $config_sha, murmur: "2"}
      ],
      nonModpackFilesToDelete: [{file: "/mods/stale.jar", sha1: "0123456789abcdef0123456789abcdef01234567", timestamp: "1786700000000"}]
    }' > "$root/host/automodpack-content.json"

  jq -n '{
    enforce: true,
    mode: "whitelist",
    operatorsBypass: false,
    requireCompanionMod: true,
    verifySignature: true,
    requiredMods: ["automodpack_mod", "hailwall", "sablecollisiondamage", "ttss_exclusive_client"],
    requiredVersions: {automodpack_mod: "4.0.6", hailwall: "1.0.3-versionlock.1"},
    whitelist: ["automodpack_mod", "hailwall", "sablecollisiondamage", "ttss_exclusive_client"]
  }' > "$root/config/hailwall.json"
}

expect_rejected() {
  local name=$1 root=$2
  if "$script_dir/verify-export.sh" "$root" > "$work/$name.log" 2>&1; then
    printf 'expected rejection: %s\n' "$name" >&2
    exit 1
  fi
}

# Given: a complete synthetic AutoModpack export with strict HailWall policy.
# When: the export verifier reads the real files and metadata.
# Then: the valid export is accepted.
valid="$work/valid"
make_fixture "$valid"
"$script_dir/verify-export.sh" "$valid" | grep -F 'export_verification=PASS' >/dev/null

# Given: one independently corrupted boundary per fixture.
# When: the same verifier evaluates each export.
# Then: every unsafe export is rejected.
unsafe="$work/unsafe"
cp -a "$valid" "$unsafe"
jq '.list[0].file = "/../escape.jar"' "$unsafe/host/automodpack-content.json" > "$unsafe/host/manifest.tmp"
mv "$unsafe/host/manifest.tmp" "$unsafe/host/automodpack-content.json"
expect_rejected unsafe_path "$unsafe"

mismatch="$work/mismatch"
cp -a "$valid" "$mismatch"
printf 'tampered\n' >> "$mismatch/host/main/mods/example.jar"
expect_rejected hash_mismatch "$mismatch"

worldedit="$work/worldedit"
cp -a "$valid" "$worldedit"
cp "$worldedit/host/main/mods/example.jar" "$worldedit/host/main/mods/worldedit-mod.jar"
jq '.list += [.list[0] | .file = "/mods/worldedit-mod.jar"]' "$worldedit/host/automodpack-content.json" > "$worldedit/host/manifest.tmp"
mv "$worldedit/host/manifest.tmp" "$worldedit/host/automodpack-content.json"
expect_rejected worldedit "$worldedit"

hailwall="$work/hailwall"
cp -a "$valid" "$hailwall"
jq '.enforce = false' "$hailwall/config/hailwall.json" > "$hailwall/config/hailwall.tmp"
mv "$hailwall/config/hailwall.tmp" "$hailwall/config/hailwall.json"
expect_rejected hailwall_disabled "$hailwall"

printf 'verify_export_tests=PASS cases=5\n'
