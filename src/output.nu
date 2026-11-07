# ==================================================================================================
# Clean Gone: Output
# ==================================================================================================

# The non-blank lines of `text`, trimmed, since glab pads its error box with spaces.
export def error-lines [text: string]: nothing -> list<string> {
  $text
  | lines
  | str trim
  | where $it != ""
}

export def plural [count: int, noun: string]: nothing -> string {
  if $count == 1 { $"1 ($noun)" } else { $"($count) ($noun)s" }
}

export def die [msg: string] {
  print -e $"error: ($msg)"
  exit 2
}

export def print-skip [subject: string, problem: string, details: list<string> = []]: nothing -> nothing {
  print $"SKIP ($subject): ($problem)"
  for detail in $details {
    print $"    ($detail)"
  }
}
