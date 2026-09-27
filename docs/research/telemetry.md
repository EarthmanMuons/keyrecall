# What telemetry should answer

> **Status:** an audit, not a build. It names the questions real practice has to
> settle, what each needs, whether the device already keeps it, and what an
> upload may carry. Sending anything is a separate project; what this settles is
> that the evidence exists locally when that project starts.

The principle is in
[`../system/history.md`](../system/history.md#5-telemetry-a-projection-at-an-export-boundary):
telemetry is an opt-in, minimized, versioned projection computed on the device,
never a journal upload, and a field belongs in it because a question needs it.
This document is the list of questions, and the test each field has to pass.

## The test for a field

A field is collected when all of these hold:

1. it answers a named question below;
2. the answer can change a named parameter, gate, policy, or product decision;
3. it cannot be computed from the fields already in the projection;
4. it carries no more about the person than the question needs.

The third is where most candidate fields fail. The projection runs on the
device, where the whole journal and replay are available, so anything that
replay can derive, a competency mean, an elapsed interval, the breadth a learner
had when harmonic minor first appeared, is computed there and sent as a value
rather than reconstructed centrally from a history that was never sent.

## The questions

Each question names what it could change. Sources are the attempt record
(`AttemptRecord`), the profile, the acquisition journal, the feedback exposure
stream, and replay over them.

| Question                                                                                        | Could change                                  | Needs                                                                                                   | Local status |
| ----------------------------------------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------ |
| Retrieval calibration: predicted against factual retrieval, by band, interval, guidance         | memory parameters, probe spacing              | predicted retrieval, factual retrieval, guidance, elapsed interval, material maturity, scheduler intent | derived      |
| Posterior behavior: does uncertainty contract with spaced evidence and reverse on contradiction | the consolidation envelope                    | the history per learner, replayed                                                                       | derived      |
| Recovery and probes: episode length, time to the next factual observation, probe yield          | recovery and probe policy                     | challenge bypass, guidance, outcomes in order                                                           | persisted    |
| Scheduler distributions: concentration, revisit gaps, bypass mix, no-admission frequency        | guardrails on every scheduler change          | material, bypass, timing, and how each sitting ended                                                    | partial      |
| Session effects: warm-up and fatigue shapes within a sitting                                    | a transient session state (roadmap 2.1)       | order within the sitting, gaps between attempts, active playing time, interruptions                     | partial      |
| Family transfer: does one family's playing predict the other's, at which shapes                 | shared competencies, family transfer strength | predicted execution and its components, managed execution, family, shape                                | derived      |
| Altered-form breadth: how breadth at a first harmonic or melodic encounter relates to it        | the six and eight thresholds                  | breadth at introduction, the first attempts' outcomes                                                   | derived      |
| Placement priors: how far each self-report sits from the evidence that follows                  | placement priors                              | placement tier, early predictions and outcomes                                                          | persisted    |
| Goal effects: what arriving and the shape frontier do to real learning and adherence            | the progress preference, goal definitions     | the goal and focus each decision was made under                                                         | persisted    |
| Coverage standards: is 0.5 timing what a from-memory requirement should ask of a beginner       | the completion policy                         | motor scores of retrieved attempts over time                                                            | persisted    |
| Presentation and feedback: do cues, fingering, or feedback levels move later attempts           | presentation policy                           | presentation record, feedback exposure                                                                  | persisted    |
| Measurement validity: does timing quality differ by transport, and should it pool               | timing floors, per-transport calibration      | which clock measured each attempt's timing                                                              | missing      |

"Derived" means every input is persisted and the value is computed by replay on
the device. "Partial" and "missing" are the gaps below.

The two calibration questions left open by the synthetic work are both
derivable: [`experiments/family-transfer.md`](experiments/family-transfer.md)
splits a prediction into its competency sources from state alone, and
[`experiments/altered-forms.md`](experiments/altered-forms.md) recomputes
breadth at introduction from history.

## What the device does not keep

Four things the questions need were written nowhere, and could not be recovered
later because nothing downstream held them. Each says below whether it now is.

**The goal and focus a decision was made under.** The profile stores its current
goal and the focus lives only in memory, so a history could not say which goal
chose any attempt. Arriving and the shape frontier behave differently per goal,
and every scheduler distribution needs to be read per scope. Recorded since
attempt schema version 6: the goal id, its curriculum and version, and the
focus, on each decision.

**Attempt timing.** An attempt records when it was decided, and the transcript
it was measured from is discarded at close. Nothing keeps when the first note
came, how long the playing took, or when it closed, so active practice time and
the gaps a warm-up or fatigue analysis reads are unrecoverable, and so is the
time to the first note, the natural latency signal for retrieval. The fix is a
few durations on the record, measured from the moment the attempt opened, and
whether the app lost the foreground during it.

**Which clock measured the timing.** An attempt with timing says so by carrying
continuity and stability, but not which transport or clock shape produced them.
Transports differ in resolution and jitter, and pooling across them without
knowing which is which risks reading the device as the learner. The fix is the
clock shape's identifier on the record, which names a class of transport and
nothing about the instrument.

**How a sitting ended.** Caught up, blocked, and left are decisions that write
no attempt, so the no-admission frequency the roadmap asks for is invisible.
Unlike the three above, this wants a small per-profile event stream rather than
a field, since the event has no attempt to sit on, and it is the one gap that
can wait: no calibration depends on it, only a guardrail.

Two things look like gaps and are not. A learner who stops or declines an
attempt is recorded with that termination. Whether a presented pick was a shape
step rather than ranking's first choice is not kept, but whether it was a step
past the demonstrated shapes is derivable from history, which is the question an
analysis asks.

## What an upload may carry

Per attempt, a compact event, computed on the device:

- the model, scheduler, presentation policy, and app versions, and the telemetry
  schema version, without which nothing can be interpreted;
- the exercise as vocabulary: family, material, hands, span, direction, motion,
  tempo, guidance;
- the decision: tier and its reason, whether it was in band, the bypass, the
  arriving flag, the goal and focus;
- the prediction's channels and, where a question needs them, derived state such
  as the competency sources of the execution prediction;
- the outcome's scalar scores and termination, the presentation record, and the
  timing durations;
- time as position, not date: days since the subject's first attempt, the
  attempt's order in its sitting, seconds since the previous attempt, and a
  coarse local time-of-day band.

Per subject, once: the placement tier, and nothing else about the person.

**Never:** the display name, the local profile id, an install id, absolute
timestamps, the transcript or anything note by note, raw MIDI, the instrument's
name or identifiers, or precise location or time zone. None of the questions
needs them, and the transcript in particular is what no local store keeps
either.

## Identity, opt-out, and reset

**A subject id minted for telemetry.** Random, created when a profile opts in,
and unrelated to the local profile id, which a future sync will merge on and
which must therefore never leave in this form. It relates one profile's attempts
to each other and to nothing else. Profiles on one install are not linked:
nothing asks about households, and linking them would reveal one.

**Opting out** stops the projection and keeps the subject id locally, so a
deletion request can name it. **Opting back in** mints a new id: a gap in a
history is honest, and a silently resumed one is not.

**Erasing a profile** erases its subject id with it, after sending the deletion
request if the profile had opted in. **Resetting progress** is the same as
erasing for this purpose, since the history the subject described is gone.

**Model versions change what a field means**, and every event carries them, so a
question is always answered within one version or across a replay that states
which.

## What this settles

The four gaps are the local work. The first three are fields on the attempt
record and belong in the next journal schema; the fourth waits until a guardrail
needs it. Everything else in the table is already persisted or derivable, and
the projection itself, its schema, consent, and transport, is the separate
project this prepares for.
