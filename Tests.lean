-- ABOUTME: Run deterministic scenarios and bounded exploration for both standards models.
-- ABOUTME: Treat a failed assertion as a failing process for local runs and CI.
import LeanForStandardization.HappyEyeballs.Tests
import LeanForStandardization.ERC8004.Tests

def main : IO Unit := do
  LeanForStandardization.HappyEyeballs.runTests
  LeanForStandardization.ERC8004.runTests
  IO.println "All model tests passed."
