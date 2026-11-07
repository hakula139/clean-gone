# ==================================================================================================
# Clean Gone: Requests Tests
# ==================================================================================================

use std/assert

use ./tests/repo.testlib.nu *

def "test the forge is detected from the origin URL or its SSH host alias" [] {
  let hostnames = {
    "git@work": "github.com"
    "deploy@work": "github.com"
    work: "git.example"
    "github.com-443": "ssh.github.com"
    "github.com-mirror": "git.example"
  }
  let cases = [
    {
      name: "a URL"
      url: "https://github.com/example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: true
    }
    {
      name: "a URL mapped to a mirror by insteadOf"
      url: "https://github.com/example/app.git"
      base: "https://git.example/github/"
      prefix: "https://github.com/"
      extra: ""
      github: true
    }
    {
      name: "a shorthand URL rewritten by insteadOf"
      url: "gh:app.git"
      base: "git@github.com:example/"
      prefix: "gh:"
      extra: ""
      github: true
    }
    {
      name: "several configured URLs"
      url: "https://github.com/example/app.git"
      base: ""
      prefix: ""
      extra: "https://github.com/example/other.git"
      github: true
    }
    {
      name: "an SSH URL"
      url: "ssh://git@github.com:22/example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: true
    }
    {
      name: "an scp-like URL"
      url: "git@github.com:example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: true
    }
    {
      name: "an SSH host alias"
      url: "git@work:example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: true
    }
    {
      name: "an SSH host alias selected by its user"
      url: "ssh://deploy@work/example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: true
    }
    {
      name: "an SSH host alias over port 443"
      url: "git@github.com-443:example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: true
    }
    {
      name: "an alternate SSH host"
      url: "ssh://git@ssh.github.com/example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: true
    }
    {
      name: "an SSH host alias to another host"
      url: "git@github.com-mirror:example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: false
    }
    {
      name: "a URL whose SSH alias would map it to GitHub"
      url: "https://work/example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: false
    }
    {
      name: "a GitLab URL"
      url: "git@gitlab.com:example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: false
    }
    {
      name: "a local path"
      url: "/srv/example/app.git"
      base: ""
      prefix: ""
      extra: ""
      github: false
    }
  ]

  for case in $cases {
    let repo = (make-repo)
    let tip = (git-in $repo.main rev-parse origin/main)
    let worktree = (add-worktree $repo "wt")
    git-in $repo.main remote set-url origin $case.url
    if ($case.base | is-not-empty) {
      git-in $repo.main config --global $"url.($case.base).insteadOf" $case.prefix
    }
    if ($case.extra | is-not-empty) {
      git-in $repo.main config --add remote.origin.url $case.extra
    }
    let requests = (
      if $case.github {
        [{number: 7, headRefName: "feat/wt", state: "MERGED", headRefOid: $tip}]
      } else {
        [(mr 3 "feat/wt" "merged" $tip)]
      }
    )
    let lookup = (
      if $case.github {
        [
          pr list
            --repo "example/app"
            --head "feat/wt"
            --state all
            --json "number,state,headRefOid"
        ]
      } else {
        [
          mr list
            --source-branch "feat/wt"
            --all
            --output json
        ]
      }
    )

    let result = (clean $repo --requests $requests --ssh-hostnames $hostnames)

    let evidence = (
      if $case.github { "pull request #7 is merged" } else { "merge request !3 is merged" }
    )
    assert equal $result.lines (removal $worktree $evidence --branch "feat/wt" --force) $case.name
    assert equal $result.exit_code 0 $case.name
    assert-removed $repo $worktree $case.name
    assert equal $result.calls [{args: $lookup}] $case.name
  }
}

def "test a rejected SSH configuration ends the run only when it is resolved" [] {
  let error = "Bad configuration option: usekeychain"
  let cases = [
    {
      name: "an SSH origin"
      url: "git@work:example/app.git"
      base: ""
      prefix: ""
      exit_code: 2
      stdout: ""
      stderr: $"error: resolving git@work through ssh failed\n    ($error)\n"
    }
    {
      name: "a GitHub origin beside a rewritten SSH URL"
      url: "https://github.com/example/app.git"
      base: "git@github.com:"
      prefix: "https://github.com/"
      exit_code: 0
      stdout: "Nothing to clean up.\n"
      stderr: ""
    }
  ]

  for case in $cases {
    let repo = (make-repo)
    git-in $repo.main remote set-url origin $case.url
    if ($case.base | is-not-empty) {
      git-in $repo.main config --global $"url.($case.base).insteadOf" $case.prefix
    }

    let result = (clean $repo --ssh-error $error --ssh-exit 255)

    assert equal $result.exit_code $case.exit_code $case.name
    assert equal $result.stdout $case.stdout $case.name
    assert equal $result.stderr $case.stderr $case.name
  }
}

def "test a request whose head lacks the branch tip leaves the branch unfinished" [] {
  let cases = [
    {
      name: "a later commit on the branch"
      sha: {|repo| git-in $repo.main rev-parse origin/main }
    }
    {
      name: "a head missing from the repository"
      sha: {|repo| "0123456789abcdef0123456789abcdef01234567" }
    }
  ]

  for case in $cases {
    let repo = (make-repo)
    let worktree = (add-worktree $repo "wt")
    commit-files $worktree {"later.txt": "later\n"} "feat: add later work"
    make-dirty $worktree 3day

    let result = (clean $repo --requests [(mr 1 "feat/wt" "merged" (do $case.sha $repo))])

    let problem = "uncommitted work, last touched 3 days ago. Review whether it needs an MR."
    assert equal $result.lines [$"SKIP ($worktree): ($problem)"] $case.name
    assert equal $result.exit_code 1 $case.name
    assert-kept $repo $worktree "feat/wt" $case.name
  }
}

def "test a failed lookup skips the worktree" [] {
  let repo = (make-repo)
  let worktree = (add-worktree $repo "wt")
  make-idle $worktree
  let forge_error = (
    ["    " "  ERROR  " "    " "  No remote matches GITLAB_HOST.  " "  Add a matching remote.  "]
    | str join "\n"
  )

  let result = (clean $repo --forge-error $forge_error)

  assert equal $result.lines [
    $"SKIP ($worktree): looking up its requests failed"
    "    ERROR"
    "    No remote matches GITLAB_HOST."
    "    Add a matching remote."
  ]
  assert equal $result.exit_code 1
  assert-kept $repo $worktree "feat/wt" "lookup failure"
}

def "test an open request keeps its worktree untouched" [] {
  let cases = [
    {
      name: "uncommitted work"
      dirty: true
      requests: {|tip| [(mr 3 "feat/wt" "opened" $tip)] }
    }
    {
      name: "an idle clean worktree"
      dirty: false
      requests: {|tip| [(mr 3 "feat/wt" "opened" $tip)] }
    }
    {
      name: "an open request beside a newer merged one"
      dirty: false
      requests: {|tip| [(mr 3 "feat/wt" "opened" $tip) (mr 4 "feat/wt" "merged" $tip)] }
    }
  ]

  for case in $cases {
    let repo = (make-repo)
    let tip = (git-in $repo.main rev-parse origin/main)
    let worktree = (add-worktree $repo "wt")
    if $case.dirty {
      make-dirty $worktree
    }
    make-idle $worktree

    let result = (clean $repo --requests (do $case.requests $tip))

    assert equal $result.lines ["Nothing to clean up."] $case.name
    assert equal $result.exit_code 0 $case.name
    assert-kept $repo $worktree "feat/wt" $case.name
  }
}
