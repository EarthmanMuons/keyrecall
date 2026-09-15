# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Fixed

- Curriculum completion assesses what a performance demonstrated instead of
  borrowing the learner model's execution predicate. `assessRequirementAttempt`
  reads one attempt criterion by criterion: completion, tempo, pitch integrity,
  retrieval, timing, and coordination where both hands played. A requirement is
  covered only when every criterion it names was met, so alternating octave
  errors at full tempo no longer cover one, and a criterion the attempt carried
  no evidence about reads unknown rather than passing.
- Tempo is assessed from the pace played rather than the pace requested. The
  requirement's structure is matched without its tempo criterion, and the
  criterion is read as the requested tempo times the achieved ratio, so a clean
  60 BPM performance no longer covers a 120 BPM requirement and a fast
  performance under a slower request can.
- `PracticePlan.resolve` returns `ResolvedPlan` or `UnresolvablePlan` and
  validates before selecting. An unknown `goalId` and a focus naming material
  vocabulary this build has no meaning for both fail, rather than resolving to
  unrestricted practice. A persisted focus missing a facet, or one that narrows
  nothing, is refused when it is read.
- An exclusive focus's completion targets are the requirements it named.
  Requirements retained because they prepare one carry a support role instead,
  so a target that also supports a selected target no longer joins the
  intersection it was excluded from.
- `PracticePlan.focusedOn` collapses a focus that narrows nothing to practicing
  normally, so nothing durable holds a focus over the whole catalog. A stored
  focus whose facets are all present and empty reads back as that unfocused plan
  rather than being refused, since a build whose chooser offered it could write
  one; a facet that is missing entirely is still unreadable.
- `goalEmphasisOf` takes the strongest weight over a material before dropping
  neutral results, so `0.5` beside `1.0` no longer de-emphasizes the material
  something else asked for.

### Changed

- Arpeggio candidate generation uses the shared `playableOn` instrument gate, so
  a four-octave hands-together arpeggio, which V1's hand placement spreads over
  eight octaves, is no longer offered on any keyboard.
- `SchedulerHost` binds the resolved scope it decides against, along with the
  learner and policy constants to decide with, and takes the due requirement ids
  for a slot. A host that decides elsewhere establishes the candidate envelope
  once rather than sending it with every request, and cannot decide with a
  different learner than the session's.
- `PracticeBlocked` carries the blocked reason directly, and its full selection
  only where the decision was computed in this isolate.
- Candidate assembly deduplicates by material rather than by exercise, which
  removed about 60 ms from every full-catalog decision.

### Added

- `CoordinationSample.looseMomentsAt` and `scoreUnder`, which replay one series
  against a synchronized bound it was not recorded under, so a threshold can be
  argued from what the playing would have read rather than from how a sitting
  felt.

- `CoordinationSample` and the store's coordination log, one append-only
  diagnostic line per measured two-hand attempt. It keeps every measurable
  moment's signed spread with its position, beside the realization, the achieved
  tempo, the coordination score, the synchronized bound in force, and whether
  the learner was told the hands came apart. Nothing replays it, erasing a
  profile takes it along, and a failed write leaves the attempt alone: the
  attempt record keeps a blended score that cannot be read back as the
  milliseconds it came from, and whether that bound is the right one is a
  question about the distribution.

- `PracticePlan`, what one profile is working toward and what it is drawing from
  now, with `MaterialFocus` expressing a focus as material characteristics
  rather than as a list of ids. It resolves against a catalog into the goal and
  focus scope resolution already takes, emphasizing or excluding.
- `PracticeStore.loadPracticePlan` and `savePracticePlan`, one overwritable slot
  per profile. `FilePracticeStore` keeps it in `plan.json`, and erasing a
  profile takes it along.
- `catalogRequirementId`, the requirement id a goal with no curriculum of its
  own gives a material, so a focus can address what that goal generated.
- `goalEmphasisOf`, the emphasis a resolved scope puts on each of its materials,
  which both hosts derive once from the bound scope.
- `SchedulerHost`, the seam a session decides through, and `SchedulerVerdict`,
  one slot's decision reduced to what a session acts on, carrying the epoch it
  answered and a `SittingDecisionEffect` to apply. `InProcessScheduler` keeps
  the existing behavior and is the default.
- `IsolateScheduler`, a host that decides on a worker isolate holding the
  sitting's resolved scope. Requirement ids travel instead of the candidate
  envelope, and only the winning candidate comes back. Losing a worker fails
  that request alone, applying nothing and writing nothing.
- `PracticeSession.decisionEpoch`, the version of the scheduler inputs a session
  owns, and `PracticeSuperseded`, the outcome of a verdict that arrives for
  inputs that have since moved.
- Resolved practice scopes carry each active material family's entry tempo into
  the generic scheduler policy used for that scope.
- `ArpeggioPracticePolicy`, which lets simulation vary the provisional initial
  tempo and compare right-hand, separate-hand, and ascending-and-descending
  acquisition floors without changing the shipped defaults.
- Arpeggio families generate one-, two-, and four-octave realizations only when
  canonical fingerings exist for every requested hand. Unsupported inversion
  requirements resolve as unrealizable instead of receiving guessed exercises.
- `PracticeSession`, the attempt transaction: it persists the decision before
  presenting, commits the outcome as an attempt, and recovers from a run
  interrupted anywhere in that sequence.
- Reopening a sitting rebuilds the scheduler's recency and realization-family
  allocation windows from the tail of the journal, so restarting the app does
  not clear the pacing pressure the work before it built up.
- `PendingDecision`, the durable record of what was presented but not yet
  answered, deliberately outside the journal.
- `PracticeStore`, the storage port, with an in-memory implementation and
  `FilePracticeStore`, which appends to ordinary files and repairs a torn tail.
- Commit computes the transition on a copy and replaces canonical state only
  after a durable append, so a storage failure that leaves the process running
  can be retried safely.
- Recovery validates a pending decision's profile, journal position, and
  timestamp before accepting it.
- `ProfileRepository`, with in-memory and file-backed implementations, covering
  profile creation, listing, renaming, and selection. Kept separate from
  practice storage, and deliberately without deletion.
- The execution frontier: `MaterialExecutionState` records the fastest tempo a
  learner has demonstrated at each span, for that material with that hand. A
  tempo per span rather than two maxima, because a widest span and a fastest
  tempo are not a place anybody has been. Durable learner state, reconstructed
  by replay from the same exercise and outcome stream the residual beside it is.
- Self-describing profile directories: each profile writes its own
  `profile.json` beside its journal, so a directory holding both is enough to
  reopen that learner with no file outside it. The roster is scanned from those
  records and `profiles.json` holds only which profile is active, which makes
  losing it cost a selection rather than every history on the install.
- `selectedOrOldest()`, which resolves who is active and creates nobody. It
  replaced `selectedOrDefault()`, whose fabricated profile started from a
  placement nobody chose and nobody could change afterwards; an install with no
  profile is now an onboarding state the app resolves by asking.
- `create` takes a required `PlacementTier`, and `Profile` carries it. It is the
  initial condition replay propagates from, so a profile that does not record it
  cannot reproduce its own state, and an index entry without one is refused
  rather than defaulted.
