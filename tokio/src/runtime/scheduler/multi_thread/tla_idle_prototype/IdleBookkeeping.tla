-------------------------- MODULE IdleBookkeeping --------------------------
EXTENDS FiniteSets, Naturals, Sequences, TLC

\* PROTOTYPE: Model only the scheduler slice involved in tokio-rs/tokio#8372.
\* ReconcileTraceWake selects the pre-fix or post-fix transition.

CONSTANTS Workers, CounterMod, ReconcileTraceWake

ASSUME /\ Workers # {}
       /\ Cardinality(Workers) < CounterMod
       /\ ReconcileTraceWake \in BOOLEAN

WorkerStates == {"Running", "Parked", "AwakeForTrace", "Tracing"}

VARIABLES
    workerState,
    sleepers,
    numUnparked,
    traceRequested,
    remoteWork,
    workCompleted

vars == <<workerState, sleepers, numUnparked,
          traceRequested, remoteWork, workCompleted>>

SeqToSet(s) == {s[i] : i \in 1..Len(s)}

RemoveAt(s, at) ==
    [i \in 1..(Len(s) - 1) |-> IF i < at THEN s[i] ELSE s[i + 1]]

RemoveOne(s, value) ==
    RemoveAt(s, CHOOSE i \in 1..Len(s) : s[i] = value)

IncUnparked(value) == (value + 1) % CounterMod

DecUnparked(value) ==
    IF value = 0 THEN CounterMod - 1 ELSE value - 1

Init ==
    /\ workerState = [w \in Workers |-> "Running"]
    /\ sleepers = <<>>
    /\ numUnparked = Cardinality(Workers)
    /\ traceRequested = FALSE
    /\ remoteWork = FALSE
    /\ workCompleted = FALSE

Park(w) ==
    /\ workerState[w] = "Running"
    /\ ~traceRequested
    /\ ~remoteWork
    /\ workerState' = [workerState EXCEPT ![w] = "Parked"]
    /\ sleepers' = Append(sleepers, w)
    /\ numUnparked' = DecUnparked(numUnparked)
    /\ UNCHANGED <<traceRequested, remoteWork, workCompleted>>

\* notify_all physically wakes every parked worker but does not itself touch
\* Idle. Each worker must reconcile the logical parked state before tracing.
RequestTrace ==
    /\ ~traceRequested
    /\ \A w \in Workers : workerState[w] = "Parked"
    /\ workerState' = [w \in Workers |-> "AwakeForTrace"]
    /\ traceRequested' = TRUE
    /\ UNCHANGED <<sleepers, numUnparked, remoteWork, workCompleted>>

BeginTrace(w) ==
    /\ workerState[w] = "AwakeForTrace"
    /\ traceRequested
    /\ w \in SeqToSet(sleepers)
    /\ workerState' = [workerState EXCEPT ![w] = "Tracing"]
    /\ sleepers' =
          IF ReconcileTraceWake THEN RemoveOne(sleepers, w) ELSE sleepers
    /\ numUnparked' =
          IF ReconcileTraceWake THEN IncUnparked(numUnparked) ELSE numUnparked
    /\ UNCHANGED <<traceRequested, remoteWork, workCompleted>>

CompleteTrace ==
    /\ traceRequested
    /\ \A w \in Workers : workerState[w] = "Tracing"
    /\ workerState' = [w \in Workers |-> "Running"]
    /\ traceRequested' = FALSE
    /\ UNCHANGED <<sleepers, numUnparked, remoteWork, workCompleted>>

SubmitRemoteWork ==
    /\ ~remoteWork
    /\ \A w \in Workers : workerState[w] = "Parked"
    /\ remoteWork' = TRUE
    /\ workCompleted' = FALSE
    /\ UNCHANGED <<workerState, sleepers, numUnparked, traceRequested>>

NotifyShouldWakeup == numUnparked < Cardinality(Workers)

NotifyRemoteWork ==
    /\ remoteWork
    /\ NotifyShouldWakeup
    /\ sleepers # <<>>
    /\ LET w == Head(sleepers)
       IN  /\ workerState' = [workerState EXCEPT ![w] = "Running"]
           /\ sleepers' = Tail(sleepers)
           /\ numUnparked' = IncUnparked(numUnparked)
    /\ UNCHANGED <<traceRequested, remoteWork, workCompleted>>

RunRemoteWork(w) ==
    /\ remoteWork
    /\ workerState[w] = "Running"
    /\ remoteWork' = FALSE
    /\ workCompleted' = TRUE
    /\ UNCHANGED <<workerState, sleepers, numUnparked, traceRequested>>

Next ==
    \/ \E w \in Workers : Park(w)
    \/ RequestTrace
    \/ \E w \in Workers : BeginTrace(w)
    \/ CompleteTrace
    \/ SubmitRemoteWork
    \/ NotifyRemoteWork
    \/ \E w \in Workers : RunRemoteWork(w)

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ workerState \in [Workers -> WorkerStates]
    /\ sleepers \in Seq(Workers)
    /\ numUnparked \in 0..(CounterMod - 1)
    /\ traceRequested \in BOOLEAN
    /\ remoteWork \in BOOLEAN
    /\ workCompleted \in BOOLEAN

NoDuplicateSleepers == Len(sleepers) = Cardinality(SeqToSet(sleepers))

UnparkedInRange == numUnparked <= Cardinality(Workers)

AccountingAgrees == numUnparked = Cardinality(Workers) - Len(sleepers)

PendingWorkWakeable ==
    (remoteWork /\ \A w \in Workers : workerState[w] = "Parked") =>
        NotifyShouldWakeup

=============================================================================
