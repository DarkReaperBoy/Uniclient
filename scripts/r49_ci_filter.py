#!/usr/bin/env python3
"""R49/R50 — extend the verify.yml gui race-leg filter with the new pins
(the every-iteration discipline: each fix's pins join the CI race leg)."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
YML = ROOT / ".github" / "workflows" / "verify.yml"

OLD = "TestGiveawayPrepaidPeriodMaxGuarded'"
NEW = ("TestGiveawayPrepaidPeriodMaxGuarded|TestCallsBoxPageMergeBuildsFreshSlice"
       "|TestCallsBoxLoadTailSessionGuarded|TestCallsBoxPageMergeDedupeGuard"
       "|TestCallsBoxSessionGenBumps|TestCallsBoxClearFailedRecovers'")

data = YML.read_text()
n = data.count(OLD)
if n != 1:
    sys.exit(f"verify.yml: anchor found {n}x (want 1)")
YML.write_text(data.replace(OLD, NEW))
print("verify.yml race-leg filter extended with the 5 R49/R50 pins")
