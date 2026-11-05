#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  cd "$BATS_TEST_TMPDIR"
  mkdir -p flavors .tmp/my-avbroot-setup
  FLAVOR_DIR="$BATS_TEST_TMPDIR/flavors"
  DEBUG=''
  NO_COLOR=1
  # shellcheck disable=SC1090
  source "$REPO_ROOT/rooted-ota.sh"
  # Declarations in a sourced script are local to setup(), not the test body.
  declare -gA POTENTIAL_ASSETS=()
  declare -ga FLAVOR_PLUGINS=() FLAVOR_PLUGINS_ENABLED=()
}

@test "a flavor without its required enabled hook is rejected" {
  cat > flavors/demo.sh <<'EOF'
function flavor_demo_asset_infix() { echo demo; }
EOF
  run loadFlavorPlugins
  [ "$status" -eq 1 ]
}

@test "disabled flavors are not prepared" {
  cat > flavors/demo.sh <<'EOF'
function flavor_demo_enabled() { return 1; }
function flavor_demo_asset_infix() { echo demo; }
function flavor_demo_prepare() { touch disabled-prepared; }
EOF
  loadFlavorPlugins
  prepareFlavorPlugins
  [ ! -e disabled-prepared ]
  [ "${#FLAVOR_PLUGINS_ENABLED[@]}" -eq 0 ]
}

@test "invalid configuration is an error rather than a skipped flavor" {
  cat > flavors/demo.sh <<'EOF'
function flavor_demo_enabled() { return 23; }
function flavor_demo_asset_infix() { echo demo; }
EOF
  loadFlavorPlugins
  run prepareFlavorPlugins
  [ "$status" -eq 23 ]
}

@test "a failed prepare stops before preparing subsequent flavors" {
  cat > flavors/demo.sh <<'EOF'
function flavor_demo_enabled() { return 0; }
function flavor_demo_asset_infix() { echo demo; }
function flavor_demo_prepare() { return 23; }
EOF
  cat > flavors/other.sh <<'EOF'
function flavor_other_enabled() { return 0; }
function flavor_other_asset_infix() { echo other; }
function flavor_other_prepare() { touch other-prepared; }
EOF
  loadFlavorPlugins
  run prepareFlavorPlugins
  [ "$status" -eq 23 ]
  [ ! -e other-prepared ]
}

@test "patch argument failure stops OTA patching" {
  touch .tmp/custota.zip .tmp/oemunlockonboot.zip
  downloadAvBroot() { return 0; }
  downloadAndVerifyFromChenxiaolong() { return 0; }
  base642key() { return 0; }
  docker() { touch docker-called; }
  flavor_demo_patch_args() { return 23; }
  POTENTIAL_ASSETS[demo]=demo.zip
  OTA_TARGET=input

  run patchOTAs
  [ "$status" -eq 23 ]
  [ ! -e docker-called ]
}
