# ==================================================================================================
# Clean Gone: Agent Files
# ==================================================================================================

use ./git.nu [nul-list]
use ./output.nu [plural]

const AGENT_DIRS = [".claude/agent-memory-local" ".agents/plans"]

# Copies each ignored file under the agent directories that the main checkout lacks, and appends to
# each differing copy the lines it lacks, so the main checkout's copies only grow.
export def agent-file-moves [worktree: string, main: string]: nothing -> list<record> {
  (
    nul-list
      -C $worktree
      ls-files
        --others
        --ignored
        --exclude-standard
        -z
        --
        ...$AGENT_DIRS
    | where {|rel| ($worktree | path join $rel | path type) == "file" }
    | each {|rel|
      let file = ($worktree | path join $rel)
      let target = ($main | path join $rel)
      if not ($target | path exists) {
        return {
          kind: "copy"
          rel: $rel
          source: $file
          target: $target
        }
      }

      let existing = (open --raw $target | into string | lines)
      let missing = (
        open --raw $file
        | into string
        | lines
        | where {|line| ($line | str trim) != "" and $line not-in $existing }
        | uniq
      )
      if ($missing | is-not-empty) {
        {
          kind: "merge"
          rel: $rel
          target: $target
          lines: $missing
        }
      }
    }
    | compact
  )
}

export def move-text [move: record]: nothing -> string {
  if $move.kind == "copy" {
    $"copy ($move.rel) to the main checkout"
  } else {
    $"append (plural ($move.lines | length) 'new line') to ($move.rel) in the main checkout"
  }
}

export def apply-move [move: record]: nothing -> nothing {
  if $move.kind == "copy" {
    mkdir ($move.target | path dirname)
    ^cp $move.source $move.target
    return
  }

  let existing = (open --raw $move.target | into string)
  let terminated = ($existing | is-empty) or ($existing | str ends-with "\n")
  let separator = (if $terminated { "" } else { "\n" })
  ($separator + ($move.lines | str join "\n") + "\n") | save --append $move.target
}
