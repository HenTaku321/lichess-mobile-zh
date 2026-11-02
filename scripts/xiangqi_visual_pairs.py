"""Full visual-pair contract. The initial implementation is deliberately red on Actions."""


def count_cases(registry):
    return 0


def case_at(registry, ordinal):
    return {}


def plan_batch(registry, offset, limit):
    return []


def fingerprint(source_sha, registry, runtime):
    return ""


def evaluate_case(case, report, root, now):
    return {"status": "not_run", "reason": "Visual evidence validation is not implemented."}
