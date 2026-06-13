#!/usr/bin/env bats
# test version.sh: build.gradle / version catalog version parsing

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/helpers/setup.sh"
  load_scripts
  setup_mock_env
}

teardown() {
  teardown_mock_env
}

@test "resolve_project_version parses hardcoded version" {
  cat > "${TEST_PROJECT_ROOT}/build.gradle" << 'EOF'
dependencies {
    implementation "com.google.code.gson:gson:2.11.0"
    implementation "com.squareup.okhttp3:okhttp:4.12.0"
}
EOF
  local ver
  ver=$(resolve_project_version "com.google.code.gson" "gson")
  [ "$ver" = "2.11.0" ]
}

@test "resolve_project_version parses variable reference" {
  cat > "${TEST_PROJECT_ROOT}/build.gradle" << 'EOF'
ext {
    gsonVersion = "2.10.1"
}
dependencies {
    implementation "com.google.code.gson:gson:$gsonVersion"
}
EOF
  local ver
  ver=$(resolve_project_version "com.google.code.gson" "gson")
  [ "$ver" = "2.10.1" ]
}

@test "resolve_project_version parses version catalog (.toml)" {
  mkdir -p "${TEST_PROJECT_ROOT}/gradle"
  cat > "${TEST_PROJECT_ROOT}/gradle/libs.versions.toml" << 'EOF'
[versions]
gson = "2.10.1"

[libraries]
gson = { module = "com.google.code.gson:gson", version = "2.10.1" }
EOF
  local ver
  ver=$(resolve_project_version "com.google.code.gson" "gson")
  [ "$ver" = "2.10.1" ]
}

@test "resolve_project_version returns empty for unknown dep" {
  cat > "${TEST_PROJECT_ROOT}/build.gradle" << 'EOF'
dependencies {
    implementation "com.google.code.gson:gson:2.11.0"
}
EOF
  local ver
  ver=$(resolve_project_version "com.nonexist" "missing")
  [ -z "$ver" ]
}

@test "resolve_project_version skips comment lines" {
  cat > "${TEST_PROJECT_ROOT}/build.gradle" << 'EOF'
dependencies {
    // implementation "com.google.code.gson:gson:9.9.9"
    implementation "com.google.code.gson:gson:2.11.0"
}
EOF
  local ver
  ver=$(resolve_project_version "com.google.code.gson" "gson")
  [ "$ver" = "2.11.0" ]
}

@test "resolve_project_version returns empty when PROJECT_ROOT missing" {
  export PROJECT_ROOT="/nonexist/path"
  local ver
  ver=$(resolve_project_version "com.a" "b")
  [ -z "$ver" ]
}
