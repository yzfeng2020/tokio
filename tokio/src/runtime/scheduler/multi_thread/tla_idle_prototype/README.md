# PROTOTYPE: idle-bookkeeping model

Question: can a small TLA+ model reproduce #8372 by modeling only logical
sleepers, the bounded `num_unparked` counter, trace wakeups, re-parking, and
remote-work notification?

This is a throwaway feasibility prototype, not a complete Tokio scheduler
specification. TLC prints the full counterexample state after every transition.

Run it with one command from this directory:

```console
./check.sh
```

The script downloads the pinned TLA+ tools JAR into a temporary directory. Set
`TLA2TOOLS_JAR` to use an existing copy instead.

Expected result:

- `Buggy.cfg` finds pending remote work that `notify_should_wakeup` rejects.
- `Fixed.cfg` exhaustively checks the bounded model without violating the idle
  invariants.
