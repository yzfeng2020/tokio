# Prototype verdict

Question: can a bounded TLA+ model detect the idle-accounting failure fixed by
tokio-rs/tokio#8372?

## Result

Yes. With trace-wake reconciliation disabled, TLC produces this seven-state
counterexample:

1. The worker parks: `sleepers = <<w>>`, `numUnparked = 0`.
2. A trace request physically wakes it without changing `Idle`.
3. The worker begins and completes tracing while still logically parked.
4. It parks again: `sleepers = <<w, w>>`, `numUnparked = 3` in the model's
   two-bit bounded counter.
5. Remote work is submitted, but `numUnparked < Cardinality(Workers)` is false,
   so no parked worker is eligible for notification.

With reconciliation enabled, TLC explores all 40 reachable states in the
two-worker configuration and finds no violation of duplicate-sleeper, counter
range, accounting, or pending-work wakeability invariants.

## Limits

This deliberately models only the causal slice of #8372. It omits searching
workers, resource-driver wakes, shutdown, queue contents, atomic ordering, and
the full trace protocol. Passing the fixed model therefore validates the state
transition, not the complete scheduler.

## Upstream shape

The result is promising enough for an upstream contribution, but this prototype
should not be submitted unchanged. A maintained model should add:

- `num_searching` and the packed-state transitions;
- driver/spurious wakes and worker-side reconciliation;
- shutdown via `notify_all`;
- configurations for one, two, and three workers; and
- a pinned TLC runner in CI, with the buggy behavior retained as a documented
  counterexample or regression mutation.
