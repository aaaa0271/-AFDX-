"""Fail-closed verdict from the existing 52-test regression gate."""
import re

def verdict(text,rc,marker):
 # These are diagnostic/data lines, NOT echoed simulator commands or banners.
 lines=[re.sub(r'^#\s?','',x).strip() for x in text.splitlines()]
 clean=[re.sub(r'(?i)\b(?:failed|error)\s*=\s*0\b','',x) for x in lines]
 bad=[x for x in clean if re.search(r'(?i)(?:\bFAIL(?:ED)?\b|_FAIL\b|^ERROR\b|\*\* (?:Error|Fatal):|\bFATAL\b|_TIMEOUT\b)',x)]
 bad += [x for x in lines if re.search(r'(?i)(?:errors|fails|failed_cases|monitor_errors|failed|monitor)\s*[:=]\s*[1-9]\d*',x)]
 compile_ok=bool(re.search(r'(?m)^#?\s*Errors: 0, Warnings: \d+',text))
 terminal=any(marker in x for x in lines) and 'REGRESSION_FINAL_ERRORS=0' in lines
 finished=any('$finish' in x or '$stop' in x for x in lines)
 return ('PASS' if rc==0 and terminal and finished and compile_ok and not bad else 'FAIL'),bad

