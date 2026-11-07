# ==================================================================================================
# Clean Gone: Activity
# ==================================================================================================

use ./output.nu [die error-lines]

# The files the user's processes hold open, cwd included, as `pid`, `command`, and `name` rows.
# Without them no worktree can be shown unused, so a failed listing ends the run.
export def open-files []: nothing -> list {
  let listing = (
    ^lsof
      -n
      -P
      -w
      -u (^id -u | str trim)
      -F pcn
    | complete
  )
  if $listing.exit_code != 0 {
    die (
      error-lines $listing.stderr
      | prepend "listing open files failed"
      | str join "\n    "
    )
  }

  # `-F pcn` prints a `p` and a `c` line per process, then `f` and `n` lines per file.
  mut pid = ""
  mut command = ""
  mut files: list<record> = []
  for line in ($listing.stdout | lines) {
    let value = ($line | str substring 1..)
    match ($line | str substring 0..<1) {
      "p" => { $pid = $value }
      "c" => { $command = $value }
      "n" => {
        $files = (
          $files
          | append {
            pid: $pid
            command: $command
            name: $value
          }
        )
      }
    }
  }
  $files
}

export def holders [files: list<record>, path: string]: nothing -> list<string> {
  let prefix = $path + "/"
  (
    $files
    | where {|file| $file.name == $path or ($file.name | str starts-with $prefix) }
    | each {|file| $"($file.pid) ($file.command)" }
    | uniq
  )
}

# Pid 1 is every process's ancestor, so it never marks a lock as the calling session's.
export def ancestor-pids [snapshot: list<record>, start: int]: nothing -> list<int> {
  mut current = $start
  mut result: list<int> = []
  while $current not-in [0 1] {
    if ($current not-in $snapshot.pid) { break }
    $result = ($result | append $current)
    $current = ($snapshot | where pid == $current | get ppid | first)
  }
  $result
}

# Whose lock holds a worktree: `none`, an exited Claude Code session (`stale`), or the session
# calling this command (`own`). Claude Code writes `claude agent agent-<id> (pid <N> start <S>)`,
# and any other lock, or one naming another live session, is a `problem`.
export def lock-state [locked: oneof<string, nothing>, context: record]: nothing -> record {
  if $locked == null {
    return {kind: "none"}
  }

  let parsed = ($locked | parse --regex '^claude .*\(pid (?<pid>\d+)(?: start \d+)?\)$')
  if ($parsed | is-empty) {
    let problem = (
      if ($locked | is-empty) {
        "is locked without a reason"
      } else {
        $"is locked: ($locked)"
      }
    )
    return {problem: $problem}
  }

  let pid = ($parsed.0.pid | into int)
  if $pid not-in $context.processes.pid {
    return {kind: "stale"}
  }
  if $pid in $context.ancestors {
    return {
      kind: "own"
      pid: $pid
    }
  }
  {problem: $"is locked by another running session \(pid ($pid)\)"}
}
