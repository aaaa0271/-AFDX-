"""Trusted control-plane preflight and multi-loader transaction composition.

This module does not open a network management port. The board integrator maps
the resulting writes onto the plugin's separate trusted register interface.
"""
from policy import Rule, COMMIT


def overlaps(a: Rule, b: Rule):
    prefix = (a.peer_ip, a.local_ip, a.rx_mac, a.peer_mac & 0xffffffffff9f)
    other = (b.peer_ip, b.local_ip, b.rx_mac, b.peer_mac & 0xffffffffff9f)
    if prefix != other:
        return False
    # Loader rules intentionally follow dynamic ports and therefore overlap
    # every port-qualified rule with the same identity/VL prefix.
    if a.kind == 2 or b.kind == 2:
        return True
    return all(x == 0 or y == 0 or x == y for x, y in
               ((a.source_port, b.source_port),
                (a.destination_port, b.destination_port)))


def preflight(rules):
    if not 1 <= len(rules) <= 16:
        raise ValueError('one to sixteen rules required')
    ids = list(rules)
    if any(type(i) is not int or not 0 <= i < 16 for i in ids):
        raise ValueError('rule index')
    for i in ids:
        rules[i].words()
    for n, i in enumerate(ids):
        for j in ids[n + 1:]:
            if overlaps(rules[i], rules[j]):
                raise ValueError(f'ambiguous rules {i} and {j}')
    return {'status': 'PASS', 'rules': len(ids),
            'note': 'Per-rule maxima share finite global pools; size admission separately.'}


def transaction(rules, receipts=(), mode=2):
    """Compose verified authorizer receipts into one complete shadow table.

    Receipts are capabilities within this trusted process, not signed objects:
    never deserialize one received from the untrusted network as authorization.
    """
    preflight(rules)
    if mode not in (0, 1, 2):
        raise ValueError('mode')
    writes = []
    # Explicitly disable unused rules; do not inherit an old shadow entry.
    for i in range(16):
        writes.extend(rules[i].writes(i) if i in rules else [(0x100 + i * 64, 0)])
    grants = []
    floors = {}
    for receipt in receipts:
        words = {item['address']: item['value'] for item in receipt['writes']}
        for a, v in words.items():
            if 0x80 <= a < 0xc0:
                floors[a] = max(floors.get(a, 0), v)
        for index in range(16):
            base = 0x1000 + index * 128
            if words.get(base, 0) & 1:
                row = [words[base + 4 * k] for k in range(32)]
                rule_id = row[0] >> 4 & 15
                if rule_id not in rules or not rules[rule_id].signed_loading:
                    raise ValueError('grant has no signed-loader rule')
                grants.append(row)
    if len(grants) > 16:
        raise ValueError('grant capacity exceeded')
    identities = [(row[0] >> 4 & 15, tuple(row[12:20])) for row in grants]
    if len(set(identities)) != len(identities):
        raise ValueError('duplicate rule/filename grant')
    writes.extend(sorted(floors.items()))
    for i in range(16):
        if i < len(grants):
            writes.extend((0x1000 + i * 128 + 4 * k, v)
                          for k, v in enumerate(grants[i]))
        else:
            writes.append((0x1000 + i * 128, 0))
    writes.extend([(0, mode), COMMIT])
    return [{'address': a, 'value': v} for a, v in writes]
