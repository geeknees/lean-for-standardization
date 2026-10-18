-- ABOUTME: Evaluate a JSON event or operation trace using the selected Lean model.
-- ABOUTME: Keep parsing failures distinct from protocol-level rejected operations.
import LeanForStandardization.HappyEyeballs.Oracle
import LeanForStandardization.ERC8004.Oracle

open Lean

def main (args : List String) : IO UInt32 := do
  let stderr ← IO.getStderr
  let stdout ← IO.getStdout
  match args with
  | [track, path] =>
    try
      let source ← if path == "-" then (← IO.getStdin).readToEnd else IO.FS.readFile path
      let result := do
        let input ← Json.parse source
        match track with
        | "happy-eyeballs" => LeanForStandardization.HappyEyeballs.evalJson input
        | "erc8004" => LeanForStandardization.ERC8004.evalJson input
        | _ => Except.error s!"Unknown track: {track}"
      match result with
      | .ok output =>
        stdout.putStrLn output.compress
        return 0
      | .error message =>
        stderr.putStrLn message
        return 1
    catch error =>
      stderr.putStrLn error.toString
      return 1
  | _ =>
    stderr.putStrLn "Usage: lake exe oracle (happy-eyeballs|erc8004) FILE.json|-"
    return 1
