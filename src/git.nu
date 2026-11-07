# ==================================================================================================
# Clean Gone: Git
# ==================================================================================================

export def --wrapped git-out [...args: string]: nothing -> string {
  let r = (^git ...$args | complete)
  if $r.exit_code == 0 {
    $r.stdout | str trim
  } else {
    ""
  }
}

export def --wrapped nul-list [...args: string]: nothing -> list<string> {
  ^git ...$args
  | split row (char nul)
  | where $it != ""
}

export def --wrapped commit-count [...args: string]: nothing -> int {
  git-out rev-list --count ...$args | into int
}

# A blank field terminates each worktree's block, so the split into blocks has to happen before
# empty fields are dropped.
export def worktree-records []: nothing -> list<record> {
  (
    ^git worktree list
      --porcelain
      -z
    | split row (char nul)
    | split list ""
    | where {|block| $block | is-not-empty }
    | each {|block|
      let fields = (
        $block
        | reduce --fold {} {|field, acc|
          let parts = ($field | split row --number 2 " ")
          $acc | insert $parts.0 ($parts | get -o 1 | default "")
        }
      )
      {
        path: $fields.worktree
        head: ($fields.HEAD? | default "")
        branch: ($fields.branch? | default "" | str replace "refs/heads/" "")
        locked: $fields.locked?
        prunable: ("prunable" in $fields)
      }
    }
  )
}

export def local-branches []: nothing -> list<record> {
  (
    ^git for-each-ref refs/heads/
      --format="%(refname:strip=2)%09%(upstream:track)"
    | lines
    | parse "{name}\t{tracking}"
    | insert gone {|row| $row.tracking | str contains "gone" }
  )
}

# Tracked changes and untracked files, as absolute paths. Ignored files do not count.
export def changed-files [worktree: string]: nothing -> list<string> {
  let tracked = (
    nul-list
      -C $worktree
      diff HEAD
        --name-only
        --no-renames
        -z
  )
  let untracked = (
    nul-list
      -C $worktree
      ls-files
        --others
        --exclude-standard
        -z
  )
  $tracked ++ $untracked | each {|file| $worktree | path join $file }
}

# The age of the newest changed file, or of the worktree directory when every change is a deletion.
export def last-touched [worktree: string, files: list<string>]: nothing -> string {
  let existing = ($files | where {|file| $file | path exists })
  let paths = (if ($existing | is-empty) { [$worktree] } else { $existing })
  (
    $paths
    | each {|file| ls -D $file | get 0.modified }
    | sort
    | last
    | date humanize
  )
}

export def commit-date [rev: string]: nothing -> datetime {
  (
    git-out log $rev
      -1
      --format=%ct
    | into datetime --format "%s"
  )
}

# The newer of the last commit and the index's last write, which checkouts and staging update.
export def last-activity [worktree: record]: nothing -> datetime {
  let index = (
    git-out -C $worktree.path rev-parse
      --path-format=absolute
      --git-path index
  )
  [(commit-date $worktree.head) (ls -D $index | get 0.modified)] | math max
}
