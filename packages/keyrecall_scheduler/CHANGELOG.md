# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Fixed

- Candidate generation asks the instrument whether the exercise it would offer
  fits, rather than whether one hand's octave span does. A two-octave
  hands-together exercise needs 49 keys under V1's hand placement and no longer
  reaches a keyboard too narrow to hold it. `playableOn` is that one answer,
  shared by every family's candidate generation.
- A held tempo probe keeps its place against a newer one. Every attempt of an
  underchallenged learner opens a probe, so letting each new one displace the
  one being held held every probe forever and asked for none of them, leaving
  the requested tempo where it was.

### Added

- A novelty-load rule: each execution condition a candidate would be the
  learner's first of takes a rung of guidance support back, so two arriving
  together keep the notes on screen and three are met with the material in view.
  It counts hand configuration, contrary motion, and span, per material, and
  leaves recovery, tempo probes, and acquisition floors alone. Configured by
  `SchedulerConfig.novelty` and never empties the available set.
- A one-slot anti-echo hold on the tempo probe. A probe opened by the attempt
  just played is held back from the very next slot while anything else is worth
  doing, and survives into the slot after, where it competes normally.
  `SessionState.tempoProbeIsFresh` is what ages it.

- `GoalEmphasis`, the weight a focus puts on each material it asks for. `G(e)`
  reads it instead of returning a stub zero, centered so a slot with nothing
  emphasized ranks exactly as before. It enters through `evaluate`,
  `evaluateSlot`, and `decide`, and orders admitted candidates only: eligibility
  and challenge are untouched, and goal relevance remains the last key before
  the realization terms.
- `SchedulerPipeline.evaluateSlot`, the decision and what it owes the sitting,
  without recording it. `decide` applies that itself and is unchanged.
- `ExecutionMemo`, holding the transferable entry pace and hands-together entry
  tempo for one decision. Both were recomputed per candidate, and the first
  scans every execution residual the learner has.
- `RealizationKey`, what the guidance-independent prediction channels vary with.
  The per-slot execution, coordination, and topology caches key on it rather
  than on an exercise standing for a realization, which removes an allocation
  and three set comparisons per candidate.
- `IntroductionConfig`, an experimental cap on how much introduced-but-
  unretrieved material one scope may hold open at a time. It filters the
  available set beside realization-family pacing, never empties it, leaves
  admission untouched, and is null in `v1SchedulerConfig`. `SelectionResult`
  reports what it did as `introductions`.
- `PracticeEntryPolicy`, the family-neutral entry-tempo contract used by
  introduction, gentle admission, unmeasured-realization fit, and probes.
- Initial port of the KeyRecall V1 scheduler from the Python prototype under
  `analysis/scheduler/`: candidate generation, the eligibility, safety,
  challenge, and priority stages, per-candidate `CandidateTrace` records,
  lexicographic `RankKey` ranking, the repetition guard, and the new-material,
  guidance-probe, bootstrap-probe, recovery, and override admission exceptions.
- `v1SchedulerConfig`, at registry version `v1-3`. It began as
  `v1PrototypeSchedulerConfig`, mirroring `v1-prototype-0` in
  `analysis/scheduler/config.toml`, and was renamed when it stopped carrying
  only the prototype's values.
- A diagnostic fairness guard at selection: once enough selection opportunities
  have passed with an independence probe ranked and losing, the highest-ranked
  one is taken. Beside the repetition guard rather than in the rank key or as
  another bypass.
- An observation probe: after a run of attempts in which retrieval went
  unobserved, one retrieval-observing candidate is admitted whatever its
  predicted success, reported as `ChallengeBypass.observationProbe`.
- A tempo probe: an attempt completed cleanly, evenly, unbroken, from memory,
  and comfortably faster than requested opens a `ChallengeBypass.tempoProbe`
  context, which admits the same task at the fastest offered tempo the learner
  reached and nothing else. Exclusive and one decision long, like recovery.
- Realization-family pacing at selection, configured by `SchedulerConfig.pacing`
  and null where allocation is unpaced. Exercises declare the family keys they
  consume; a family that holds much of a rolling window with little managed
  execution to show for it has its candidates set aside, but only when another
  family offers a candidate at least as ready and never when nothing else is
  admitted. The window lives on `SessionState`, and `SelectionResult.pacing`
  reports what the filter did with each slot. The constants are provisional; see
  `docs/design/realization-family-pacing.md`.
- A form-introduction prerequisite: harmonic and melodic minor wait on a breadth
  of retrieved major and natural-minor material, spread across bands, reported
  as `harmonicMinorRepertoireBreadth` and `melodicMinorRepertoireBreadth`.
  Waived for a learner whose single-hand execution is already fluent.

### Changed

- Scheduler decisions can consume resolved family entry tempi while retaining
  the configured gentle tempo as the default for direct callers.
- Eligibility evaluates family-declared material, hand-configuration, and span
  prerequisites through generic scheduler stages. Execution thresholds use the
  candidate family's competencies, so evidence from another family cannot
  satisfy progression by accident.
- Challenge admission now consumes coordination-aware overall prediction for
  hands-together candidates. Admission exceptions are otherwise unchanged.
- The configuration classes assert their own bounds, so the shipped registry is
  checked where it is declared.
