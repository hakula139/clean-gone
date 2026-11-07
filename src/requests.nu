# ==================================================================================================
# Clean Gone: Requests
# ==================================================================================================

use ./git.nu [git-out]
use ./output.nu [die error-lines]

const GITHUB_HOSTS = ["github.com" "ssh.github.com"]

# The origin's configured URL, before `insteadOf` rewrites it, taking the first of several values.
export def configured-origin []: nothing -> string {
  (
    git-out config --get-all remote.origin.url
    | lines
    | first
    | default ""
  )
}

# The scheme, user, host, and path of `url`, from a URL or an scp-like `host:path`.
export def remote-parts [url: string]: nothing -> record {
  if ($url =~ '://') {
    let parts = ($url | url parse)
    {
      scheme: ($parts | get -o scheme | default "")
      user: ($parts | get -o username | default "")
      host: ($parts | get -o host | default "")
      path: ($parts | get -o path | default "")
    }
  } else {
    let match = ($url | parse --regex '^(?:(?<user>[^@/]+)@)?(?<host>[^/:]+):(?<path>.*)$')
    if ($match | is-empty) {
      {
        scheme: ""
        user: ""
        host: ""
        path: ""
      }
    } else {
      {
        scheme: ""
        user: ($match.0 | get -o user | default "")
        host: $match.0.host
        path: $match.0.path
      }
    }
  }
}

# Whether the parsed remote `parts` uses an SSH transport: an scp-like `host:path`, or an ssh-based
# URL scheme.
def ssh-transport [parts: record]: nothing -> bool {
  if ($parts.scheme | is-empty) { return true }
  $parts.scheme in ["ssh" "git+ssh" "ssh+git"]
}

# Whether the parsed remote `parts` names a repository on GitHub, resolving SSH host aliases through
# `ssh -G` for SSH transports. Fails when `ssh -G` rejects the configuration.
export def github-remote [parts: record]: nothing -> bool {
  let host = (
    if ($parts.host | is-empty) or not (ssh-transport $parts) {
      $parts.host
    } else {
      let target = (
        if ($parts.user | is-empty) {
          $parts.host
        } else {
          $"($parts.user)@($parts.host)"
        }
      )
      let run = (^ssh -G $target | complete)
      if $run.exit_code != 0 {
        die (
          error-lines $run.stderr
          | prepend $"resolving ($target) through ssh failed"
          | str join "\n    "
        )
      }
      (
        $run.stdout
        | lines
        | parse --regex '^hostname\s+(?<host>\S+)$'
        | get host
        | first
      )
    }
  )
  $host in $GITHUB_HOSTS
}

# Whether the requests on `origin` from `branch` make it `open`, `finished`, or `unfinished`, or the
# `problem` that leaves it unknown. Any open request keeps it open. Otherwise it is finished when
# its newest request is merged or closed and that request's head contains the branch tip, since a
# later tip holds unreviewed work. `gh` reads the requests from the context's slug, since it cannot
# resolve a remote that `insteadOf` rewrites.
export def branch-status [branch: string, context: record]: nothing -> record {
  let run = (
    if $context.github {
      (
        ^gh pr list
          --repo $context.slug
          --head $branch
          --state all
          --json number,state,headRefOid
        | complete
      )
    } else {
      (
        ^glab mr list
          --source-branch $branch
          --all
          --output json
        | complete
      )
    }
  )
  if $run.exit_code != 0 {
    return {
      problem: "looking up its requests failed"
      details: (error-lines $run.stderr)
    }
  }

  let requests = (
    $run.stdout
    | from json
    | rename --column (if $context.github { {headRefOid: sha} } else { {iid: number} })
    | update state {|request| $request.state | str lowercase | str replace "opened" "open" }
  )
  if ($requests | where state == "open" | is-not-empty) {
    return {state: "open"}
  }

  let newest = ($requests | sort-by number | last)
  if ($newest == null) or ($newest.state not-in ["merged" "closed"]) {
    return {state: "unfinished"}
  }
  let contained = (^git merge-base --is-ancestor $"refs/heads/($branch)" $newest.sha | complete)
  if $contained.exit_code != 0 {
    return {state: "unfinished"}
  }

  let prefix = (if $context.github { "pull request #" } else { "merge request !" })
  {
    state: "finished"
    evidence: $"($prefix)($newest.number) is ($newest.state)"
  }
}
