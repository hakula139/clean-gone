# ==================================================================================================
# Clean Gone: Cleanup Tests
# ==================================================================================================

use std/assert

use ./tests/repo.testlib.nu *

def "test the worktree of a finished branch is removed with its uncommitted work" [] {
  let cases = [
    {
      name: "a merged merge request"
      requests: {|tip| [(mr 2 "feat/wt" "closed" $tip) (mr 3 "feat/wt" "merged" $tip)] }
      github: false
      evidence: "merge request !3 is merged"
    }
    {
      name: "a closed merge request beside another branch's open one"
      requests: {|tip| [(mr 4 "feat/wt" "closed" $tip) (mr 5 "feat/other" "opened" $tip)] }
      github: false
      evidence: "merge request !4 is closed"
    }
    {
      name: "a merged pull request"
      requests: {|tip| [{number: 7, headRefName: "feat/wt", state: "MERGED", headRefOid: $tip}] }
      github: true
      evidence: "pull request #7 is merged"
    }
  ]

  for case in $cases {
    let repo = (make-repo)
    let worktree = (add-worktree $repo "wt")
    let tip = (commit-files $worktree {"feature.txt": "feature\n"} "feat: add feature")
    if $case.github {
      git-in $repo.main remote set-url origin "git@github.com:example/app.git"
    }
    make-dirty $worktree

    let result = (clean $repo --requests (do $case.requests $tip))

    let expected = (removal $worktree $case.evidence --branch "feat/wt" --force)
    assert equal $result.lines $expected $case.name
    assert equal $result.exit_code 0 $case.name
    assert-removed $repo $worktree $case.name
    assert not (has-branch $repo "feat/wt") $case.name
  }
}

def "test uncommitted work keeps an unfinished worktree with its age" [] {
  for file in ["draft.txt" "README.md"] {
    let repo = (make-repo)
    let worktree = (add-worktree $repo "wt")
    let path = ($worktree | path join $file)
    "edited\n" | save --force $path
    set-age $path 3day
    make-idle $worktree

    let result = (clean $repo)

    let problem = "uncommitted work, last touched 3 days ago. Review whether it needs an MR."
    assert equal $result.lines [$"SKIP ($worktree): ($problem)"] $file
    assert equal $result.exit_code 1 $file
    assert-kept $repo $worktree "feat/wt" $file
  }
}

def "test an idle clean worktree is removed and keeps a branch with unpublished commits" [] {
  let review = "last commit 3 days ago, so branch {b} stays. Review whether it needs an MR."
  let cases = [
    {
      name: "a pushed branch"
      branch: "feat/wt"
      commits: 1
      fresh: false
      idle: true
      push: true
      reason: "every commit is on a remote, last commit 3 days ago"
    }
    {
      name: "a backup branch"
      branch: "backup/wt"
      commits: 2
      fresh: false
      idle: true
      push: false
      reason: $"2 unpublished commits, ($review)"
    }
    {
      name: "an agent branch"
      branch: "worktree-agent-wt"
      commits: 1
      fresh: false
      idle: true
      push: false
      reason: $"1 unpublished commit, ($review)"
    }
    {
      name: "a fresh checkout"
      branch: "feat/wt"
      commits: 0
      fresh: false
      idle: false
      push: false
      reason: null
    }
    {
      name: "a fresh commit"
      branch: "feat/wt"
      commits: 1
      fresh: true
      idle: true
      push: true
      reason: null
    }
  ]

  for case in $cases {
    let repo = (make-repo)
    let worktree = (add-worktree $repo "wt" --branch $case.branch)
    let date = (if $case.fresh { git-date 0sec } else { git-date 3day })
    for n in 1..<($case.commits + 1) {
      with-env {GIT_COMMITTER_DATE: $date} {
        commit-files $worktree {$"note-($n).txt": "note\n"} $"docs: add note ($n)"
      }
    }
    if $case.push {
      git-in $worktree push origin $case.branch
    }
    "ignored\n" | save ($worktree | path join "build.log")
    if $case.idle {
      make-idle $worktree
    }

    let result = (clean $repo)

    if $case.reason == null {
      assert equal $result.lines ["Nothing to clean up."] $case.name
      assert-kept $repo $worktree $case.branch $case.name
      continue
    }
    let reason = ($case.reason | str replace "{b}" $case.branch)
    let branch = (if $case.push { $case.branch } else { "" })
    assert equal $result.lines (removal $worktree $reason --branch $branch) $case.name
    assert equal $result.exit_code 0 $case.name
    assert-removed $repo $worktree $case.name
    assert equal (has-branch $repo $case.branch) (not $case.push) $case.name
  }
}

def "test a detached worktree is removed only when idle and a ref holds its HEAD" [] {
  let repo = (make-repo)
  let kept = (commit-detached $repo "kept.txt")
  git-in $repo.main branch keep/local $kept
  let tagged = (commit-detached $repo "tagged.txt")
  git-in $repo.main tag v1 $tagged
  let held = (add-worktree $repo "held" --detach)
  let local = (add-worktree $repo "local" --detach --start $kept)
  let tag = (add-worktree $repo "tag" --detach --start $tagged)
  let fresh = (add-worktree $repo "fresh" --detach)
  let loose = (add-worktree $repo "loose" --detach)
  with-env {GIT_COMMITTER_DATE: (git-date 3day)} {
    commit-files $loose {"loose.txt": "loose\n"} "feat: add loose"
  }
  for worktree in [$held $local $tag $loose] {
    make-idle $worktree
  }

  let result = (clean $repo)

  let held_reason = "detached HEAD on a ref, last commit 3 days ago"
  let loose_problem = "detached HEAD with 1 commit on no ref, last commit 3 days ago"
  let local_problem = "1 unpublished commit, last commit 3 days ago"
  assert equal $result.lines (
    (removal $held $held_reason)
    ++ (removal $local $held_reason)
    ++ [$"SKIP ($loose): ($loose_problem). Review whether it needs an MR."]
    ++ (removal $tag $held_reason)
    ++ [$"SKIP keep/local: ($local_problem). Review whether it needs an MR."]
  )
  assert equal $result.exit_code 1
  for worktree in [$held $local $tag] {
    assert-removed $repo $worktree $worktree
  }
  assert-kept $repo $fresh "" "fresh"
  assert-kept $repo $loose "" "loose"
  assert (has-branch $repo "keep/local")
}
