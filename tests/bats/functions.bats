#!/usr/bin/env bats

setup() {
  # Load the functions
  source "$BATS_TEST_DIRNAME/../../dotfiles/dot_config/shell/functions.sh"
  
  # Ensure local binaries (like fzf) are in PATH
  export PATH="$HOME/.local/bin:$PATH"
  
  # Create a dummy git repo for tests
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  
  # Mock docker to prevent execution during tests
  docker() {
    echo "MOCK_DOCKER_CALLED: $@"
  }
  export -f docker
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

@test "parse_git_branch returns empty when not in git repo" {
  cd "$TEST_TEMP_DIR"
  run parse_git_branch
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "parse_git_branch returns current branch in git repo" {
  cd "$TEST_TEMP_DIR"
  git init > /dev/null
  git commit --allow-empty -m "initial commit" > /dev/null
  git checkout -b test-branch > /dev/null 2>&1
  
  run parse_git_branch
  [ "$status" -eq 0 ]
  [ "$output" = "test-branch" ]
}

@test "cdf correctly changes directory using real fzf filter" {
  cd "$TEST_TEMP_DIR"
  mkdir -p target_dir
  touch target_dir/target_file.txt
  
  # Force fzf to non-interactively filter for "target_file.txt"
  export FZF_DEFAULT_OPTS='-f target_file.txt'
  
  # Wrapper to run cdf and echo pwd in the same shell
  test_cdf() {
    # Provide input via here-string to avoid a pipeline (which would put cdf in a subshell)
    cdf <<< "target_dir/target_file.txt"
    pwd
  }
  
  run test_cdf
  
  echo "DEBUG OUTPUT: $output"
  echo "DEBUG STATUS: $status"
  
  [ "$status" -eq 0 ]
  # Ensure the output ends with the target_dir path
  [[ "$output" == *"/target_dir" ]]
}

@test "quartus-gui executes mocked docker with correct arguments" {
  cd "$TEST_TEMP_DIR"
  
  run quartus-gui
  
  [ "$status" -eq 0 ]
  # Verify our mock docker was called
  [[ "$output" == *"MOCK_DOCKER_CALLED:"* ]]
  # Verify it mounts the current directory
  [[ "$output" == *"-v $TEST_TEMP_DIR:/work"* ]]
  # Verify the image name
  [[ "$output" == *"cvsoc/quartus:23.1"* ]]
}
