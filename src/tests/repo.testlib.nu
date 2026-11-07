#!/usr/bin/env nu

# ==================================================================================================
# Clean Gone Test Repositories
# ==================================================================================================

use std/assert

const SCRIPT = path self "../clean-gone.nu"

export const MEMORY = ".claude/agent-memory-local"
export const PLANS = ".agents/plans"

# --------------------------------------------------------------------------------------------------
# Repositories
# --------------------------------------------------------------------------------------------------

# Runs Git in `dir` and returns its trimmed output, failing the test when Git fails.
export def --wrapped git-in [dir: string, ...args: string]: nothing -> string {
  let run = (^git -C $dir ...$args | complete)
  assert equal $run.exit_code 0 $"git ($args | str join ' '): ($run.stderr)"
  $run.stdout | str trim
}

# Creates a bare `origin` and its clone `app`, holding one pushed commit from 3 days ago that
# ignores agent memory, plans, and logs, with Git isolated from the host's configuration. Its `bin`
# runs the forge stub as both `glab` and `gh`.
export def --env make-repo []: nothing -> record {
  let root = (mktemp --directory | path expand)
  let config = ($root | path join "gitconfig")
  touch $config
  load-env {
    GIT_CONFIG_GLOBAL: $config
    GIT_CONFIG_NOSYSTEM: "1"
    GIT_AUTHOR_NAME: "Example Author"
    GIT_AUTHOR_EMAIL: "author@example.com"
    GIT_COMMITTER_NAME: "Example Author"
    GIT_COMMITTER_EMAIL: "author@example.com"
  }

  let bin = ($root | path join "bin")
  mkdir $bin
  for name in ["gh" "glab"] {
    ^ln -s ($env.NU_TEST_STUBS | path join "forge") ($bin | path join $name)
  }

  let origin = ($root | path join "origin.git")
  let main = ($root | path join "app")
  (
    ^git init $origin
      --quiet
      --bare
      --initial-branch main
  )
  git-in $root clone $origin $main
  let files = {
    ".gitignore": $"/($MEMORY)/\n/($PLANS)/\n*.log\n"
    "README.md": "app\n"
  }
  with-env {GIT_COMMITTER_DATE: (git-date 3day)} {
    commit-files $main $files "chore: init"
  }
  git-in $main push origin main

  {
    root: $root
    bin: $bin
    origin: $origin
    main: $main
  }
}

# Writes each file in `files`, a record of paths and contents, in `dir` and commits them as
# `subject`, returning the commit.
export def commit-files [dir: string, files: record, subject: string]: nothing -> string {
  for file in ($files | transpose path content) {
    $file.content | save --force ($dir | path join $file.path)
  }
  git-in $dir add ...($files | columns)
  git-in $dir commit -m $subject
  git-in $dir rev-parse HEAD
}

# Commits `file` `age` ago in the main checkout on a detached `origin/main` and returns the commit,
# then switches the checkout back to `main`.
export def commit-detached [repo: record, file: string, --age: duration = 3day]: nothing -> string {
  git-in $repo.main switch --detach origin/main
  with-env {GIT_COMMITTER_DATE: (git-date $age)} {
    commit-files $repo.main {$file: "content\n"} $"feat: add ($file)"
  }
  let head = (git-in $repo.main rev-parse HEAD)
  git-in $repo.main switch main
  $head
}

# A `GIT_COMMITTER_DATE` that is `age` old.
export def git-date [age: duration]: nothing -> string {
  $"@((date now) - $age | format date '%s') +0000"
}

# Adds linked worktree `name` beside the main checkout at `start`, on `branch`, or on `feat/<name>`
# unless `--detach`, and returns its path.
export def add-worktree [
  repo: record
  name: string
  --branch: string
  --detach
  --start: string = "origin/main"
]: nothing -> string {
  let path = ($repo.root | path join $name)
  if $detach {
    git-in $repo.main worktree add --detach $path $start
  } else {
    git-in $repo.main worktree add -b ($branch | default $"feat/($name)") $path $start
  }
  $path
}

# Edits a tracked file and adds an untracked one in `worktree`, the newer touched `age` ago.
export def make-dirty [worktree: string, age: duration = 1hr]: nothing -> nothing {
  "edited\n" | save --force ($worktree | path join "README.md")
  "draft\n" | save ($worktree | path join "draft.txt")
  set-age ($worktree | path join "README.md") $age
  set-age ($worktree | path join "draft.txt") ($age + 2day)
}

# Ages the index of `worktree`, so it reads as idle once its last commit is old too.
export def make-idle [worktree: string]: nothing -> nothing {
  let index = (
    git-in $worktree rev-parse
      --path-format=absolute
      --git-path index
  )
  set-age $index 2day
}

export def set-age [path: string, age: duration]: nothing -> nothing {
  ^touch -t ((date now) - $age | format date "%Y%m%d%H%M.%S") $path
}

# Pushes `branch` from the main checkout with an upstream, then deletes it on `origin` and prunes
# it locally, so its upstream reads as gone.
export def make-gone [repo: record, branch: string]: nothing -> nothing {
  git-in $repo.main push -u origin $branch
  git-in $repo.origin branch -D $branch
  git-in $repo.main fetch --prune | ignore
}

# A GitLab merge request in `glab mr list --output json` form.
export def mr [iid: int, branch: string, state: string, sha: string]: nothing -> record {
  {
    iid: $iid
    source_branch: $branch
    state: $state
    sha: $sha
  }
}

# The pid of a process that has already exited.
export def dead-pid []: nothing -> int {
  (
    ^$nu.current-exe
      --no-config-file
      --commands "print $nu.pid"
    | str trim
    | into int
  )
}

# The pid of a `sleep` that runs for a minute outside the script's ancestry. A process of another
# user, such as pid 1, would not do, since the Darwin build sandbox hides it from `ps`.
export def live-pid []: nothing -> int {
  ^sh -c 'sleep 60 >/dev/null 2>&1 & echo $!' | str trim | into int
}

export def claude-lock [pid: int]: nothing -> string {
  $"claude agent agent-a1b2c3d4 \(pid ($pid) start 1730800000\)"
}

# `lsof -F pcn` output for `processes`, each with a `pid`, a `command`, and the `files` it holds.
export def lsof-listing [processes: list<record>]: nothing -> string {
  (
    $processes
    | each {|process|
      $process.files
      | enumerate
      | each {|file| [$"f($file.index)" $"n($file.item)"] }
      | prepend [$"p($process.pid)" $"c($process.command)"]
    }
    | flatten
    | flatten
    | str join "\n"
  )
}

# --------------------------------------------------------------------------------------------------
# Runs and state
# --------------------------------------------------------------------------------------------------

# Runs the command in `cwd` with the forge listing `requests` or failing with `forge_error`, `lsof`
# printing `open` or failing with `lsof_exit`, and `ssh -G` resolving `ssh_hostnames` or failing
# with `ssh_error` and `ssh_exit`.
export def clean [
  repo: record
  --cwd: string
  --dry-run
  --requests: list<record> = []
  --forge-error: string = ""
  --open: string = ""
  --lsof-exit: int = 0
  --ssh-hostnames: record = {}
  --ssh-error: string = ""
  --ssh-exit: int = 0
]: nothing -> record {
  let argv = (if $dry_run { ["--dry-run"] } else { [] })
  let log = (mktemp)
  let run = with-env {
    PATH: ($env.PATH | prepend [$repo.bin $env.NU_TEST_STUBS])
    STUB_FORGE_ERROR: $forge_error
    STUB_LOG: $log
    STUB_LSOF_EXIT: ($lsof_exit | into string)
    STUB_LSOF_OUTPUT: $open
    STUB_REQUESTS: ($requests | to json --raw)
    STUB_SSH_ERROR: $ssh_error
    STUB_SSH_EXIT: ($ssh_exit | into string)
    STUB_SSH_HOSTNAMES: ($ssh_hostnames | to json --raw)
  } {
    cd ($cwd | default $repo.main)
    ^$nu.current-exe --no-config-file $SCRIPT ...$argv | complete
  }
  let calls = (open $log | from json --objects)
  $run
  | insert lines ($run.stdout | lines)
  | insert calls $calls
}

export def worktrees [repo: record]: nothing -> list<string> {
  (
    git-in $repo.main worktree list --porcelain
    | lines
    | where {|line| $line starts-with "worktree " }
    | each {|line| $line | str replace "worktree " "" }
  )
}

export def has-branch [repo: record, branch: string]: nothing -> bool {
  (git-in $repo.main branch --list $branch) | is-not-empty
}

export def assert-kept [repo: record, path: string, branch: string, case: string]: nothing -> nothing {
  assert ($path | path exists) $case
  assert ($path in (worktrees $repo)) $case
  if ($branch | is-not-empty) {
    assert (has-branch $repo $branch) $case
  }
}

export def assert-removed [repo: record, path: string, case: string]: nothing -> nothing {
  assert not ($path | path exists) $case
  assert ($path not-in (worktrees $repo)) $case
}

# The output lines of removing `worktree` for `reason`, with `--force`, after `steps` that precede
# the removal, and deleting `branch` unless it is empty.
export def removal [
  worktree: string
  reason: string
  --branch: string = ""
  --force
  --steps: list<string> = []
]: nothing -> list<string> {
  let remove = (if $force { "remove --force" } else { "remove" })
  let delete = (if ($branch | is-empty) { [] } else { [$"git branch -D -- ($branch)"] })
  [$"CLEAN ($worktree): ($reason)"] ++ (
    $steps ++ [$"git worktree ($remove) ($worktree)"] ++ $delete
    | each {|step| $"DONE ($worktree): ($step)" }
  )
}
