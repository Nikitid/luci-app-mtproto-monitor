# Security

MTProto proxy secrets and client network addresses are sensitive. Do not
include them in issues, logs or diagnostics.

The monitor reads socket ownership and TCP state locally, emits only numeric
aggregates and stores only aggregate history under `/tmp/mtproto-monitor`.

Firewall changes are explicit and limited to ports of detected proxy
instances. The helper creates exact TCP input rules from the `wan` zone or
disables exact matching rules, validates the complete configuration with
`fw4 check` and restores the previous UCI firewall configuration when
validation or reload fails. It refuses to close access through shared or
ranged rules because changing them could affect unrelated services.
