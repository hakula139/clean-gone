# ==================================================================================================
# Clean Gone: Agent Files Tests
# ==================================================================================================

use std/assert

use ./tests/repo.testlib.nu *

def "test agent memory and plans move into the main checkout without overwriting it" [] {
  let repo = (make-repo)
  let worktree = (add-worktree $repo "wt")
  let plans = ($worktree | path join $PLANS)
  mkdir $plans
  "tracked\n" | save ($plans | path join "tracked.md")
  git-in $worktree add --force ($plans | path join "tracked.md")
  git-in $worktree commit -m "docs: track a plan"
  let tip = (git-in $worktree rev-parse HEAD)
  "plan\n" | save ($plans | path join "notes.md")
  let main_memory = ($repo.main | path join $MEMORY)
  let memory = ($worktree | path join $MEMORY)
  mkdir ($main_memory | path join "tester") ($memory | path join "tester")
  "- [A](a.md) - a\n- [C](c.md) - c" | save ($main_memory | path join "MEMORY.md")
  "- [A](a.md) - a\n\n- [B](b.md) - b\n" | save ($memory | path join "MEMORY.md")
  "same\n" | save ($main_memory | path join "tester/same.md")
  "same\n" | save ($memory | path join "tester/same.md")
  "new\n" | save ($memory | path join "tester/.notes.md")

  let result = (clean $repo --requests [(mr 1 "feat/wt" "merged" $tip)])

  let steps = [
    $"copy ($PLANS)/notes.md to the main checkout"
    $"append 1 new line to ($MEMORY)/MEMORY.md in the main checkout"
    $"copy ($MEMORY)/tester/.notes.md to the main checkout"
  ]
  let expected = (
    removal $worktree "merge request !1 is merged" --branch "feat/wt" --force --steps $steps
  )
  assert equal $result.lines $expected
  assert equal $result.exit_code 0
  assert equal (open --raw ($main_memory | path join "MEMORY.md")) (
    "- [A](a.md) - a\n- [C](c.md) - c\n- [B](b.md) - b\n"
  )
  assert equal (open --raw ($main_memory | path join "tester/.notes.md")) "new\n"
  assert equal (open --raw ($main_memory | path join "tester/same.md")) "same\n"
  assert equal (open --raw ($repo.main | path join $"($PLANS)/notes.md")) "plan\n"
  assert not ($repo.main | path join $"($PLANS)/tracked.md" | path exists)
}
