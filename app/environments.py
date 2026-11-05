ASPEN_ENVIRONMENTS = [
    "Maestro",
    "V21",
    "SDM",
]

VALID_ASPEN_ENVIRONMENTS = set(ASPEN_ENVIRONMENTS)


def normalize_environment(value):
    normalized = value.strip() if value else ""
    aliases = {
        "network": "Maestro",
        "maestro": "Maestro",
        "v21": "V21",
        "cable": "SDM",
        "sdm": "SDM",
    }
    return aliases.get(normalized.lower(), normalized)


def is_valid_environment(value):
    return normalize_environment(value) in VALID_ASPEN_ENVIRONMENTS
