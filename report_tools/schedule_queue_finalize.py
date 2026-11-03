"""Deprecated helper; use the maintained runner."""
if __name__ == "__main__":
    raise SystemExit('Legacy detached-task finalization is disabled: a log line cannot recover a missing process exit code.\nRun report_tools/run_elinx_defense.py --out NEW_DIRECTORY, which records exit status and raw output.\nUse report_tools/finalize_elinx.py --run FINISHED_DIRECTORY only to index evidence.\n')
