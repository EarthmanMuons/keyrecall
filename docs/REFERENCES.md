# References

The research bibliography. Every academic and pedagogical source KeyRecall's
design draws on, in one place and one format, with a line on what we actually
took from it.

This is not an index of every URL in the repository. Tool documentation,
standards, and competitor product pages live where they are used. What belongs
here is evidence for a design choice.

Citation keys are used by the research documents so a source is written out
once. **A document that cites one still says what the source established**, in
its own prose: the bibliography removes duplication, not explanatory context.

A source appearing here is not a claim that it prescribes KeyRecall's design.
Most of what KeyRecall does is synthesis, and
[`research/foundations/literature.md`](research/foundations/literature.md) is
explicit about which principles are strongly supported and which are our own
engineering judgment.

## Learning and memory

**[Cepeda2006]** Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer,
D. (2006). Distributed practice in verbal recall tasks: A review and
quantitative synthesis. _Psychological Bulletin_, 132(3), 354-380.
<https://doi.org/10.1037/0033-2909.132.3.354> → The spacing effect, and that
optimal gap grows with the retention interval. The reason review is scheduled
against predicted decay rather than a fixed cadence.

**[Settles2016]** Settles, B., & Meeder, B. (2016). A trainable spaced
repetition model for language learning. _ACL 2016_.
<https://doi.org/10.18653/v1/P16-1174> → Half-Life Regression. The shape of
`MaterialMemoryState`: exact-item memory as a half-life fitted from observed
recall, separate from general skill.

**[PavlikAnderson2008]** Pavlik, P. I., Jr., & Anderson, J. R. (2008). Using a
model to compute the optimal schedule of practice. _Journal of Experimental
Psychology: Applied_, 14(2), 101-117.
<https://doi.org/10.1037/1076-898X.14.2.101> → ACT-R-derived practice
optimization: scheduling by predicted activation rather than by a fixed queue.

**[Mettler2013]** Mettler, E., Massey, C. M., & Kellman, P. J. (2013). Adaptive
response-time-based category sequencing in perceptual learning. _Journal of
Experimental Psychology: General_.
<https://pmc.ncbi.nlm.nih.gov/articles/PMC6124487/> → ARTS. Precedent for
sequencing on a continuous readiness signal rather than on binary mastery.

**[Tatel2025]** Tatel, C. E., & Ackerman, P. L. (2025). Meta-analysis of
procedural skill retention and decay. _Psychological Bulletin_.
<https://pubmed.ncbi.nlm.nih.gov/40455501/> → Procedural skill decays with
elapsed time, so material-specific readiness is not a monotonic accumulation of
history. The basis for mean reversion in `MaterialExecutionState`.

**[Wiseheart2017]** Wiseheart, M., D'Souza, A. A., & Chae, B. (2017). Lack of
spacing effects during piano learning. _PLOS ONE_.
<https://pubmed.ncbi.nlm.nih.gov/28843958/> (and the surgical motor-skill
distributed-practice review at the same entry) → A limit, deliberately recorded:
verbal spacing results do not transfer wholesale to motor practice. Why
KeyRecall's spacing claims are narrowed to retrieval of material rather than to
motor execution.

**[Krakauer2006]** Krakauer, J. W., & Shadmehr, R. (2006). Consolidation of
motor memory. _Trends in Neurosciences_.
<https://pmc.ncbi.nlm.nih.gov/articles/PMC2553888/> → Consolidation as a slower
envelope beneath current performance. The basis for retained consolidation and
for savings on reacquisition. Savings distinguished from long-term motor memory:
<https://pmc.ncbi.nlm.nih.gov/articles/PMC10138789/>

## Motor learning

**[GuadagnoliLee2004]** Guadagnoli, M. A., & Lee, T. D. (2004). Challenge point:
A framework for conceptualizing the effects of various practice conditions in
motor learning. _Journal of Motor Behavior_, 36(2), 212-224.
<https://doi.org/10.3200/JMBR.36.2.212-224> → The challenge point framework, and
directly the shape of the admission band: difficulty should sit where
information is maximized, which is neither easy nor overwhelming.

**[WinsteinSchmidt1990]** Winstein, C. J., & Schmidt, R. A. (1990). Reduced
frequency of knowledge of results enhances motor skill learning. _Journal of
Experimental Psychology: Learning, Memory, and Cognition_.
<https://pubmed.ncbi.nlm.nih.gov/7886280/> → The guidance hypothesis. Why
concurrent feedback is treated as support that must fade rather than as a free
improvement, and why fully cued practice earns no retrieval credit.

**[Salmoni1984]** Salmoni, A. W., Schmidt, R. A., & Walter, C. B. (1984).
Knowledge of results and motor learning: A review and critical reappraisal.
_Psychological Bulletin_. → The same distinction, established earlier:
performance during practice is not learning.

**[Winstein1994]** Winstein, C. J., Pohl, P. S., et al. (1994). Effects of
physical guidance and knowledge of results on motor learning: Support for the
guidance hypothesis. _Research Quarterly for Exercise and Sport_, 65(4).
PMID 7886280. → Physical guidance specifically, which is the closest analogue to
an on-screen cue during performance.

**[SatoKlemm2025]** Sato-Klemm, M., Williams, A. M., Chisholm, A. E., & Lam, T.
(2025). Comparing the effects of faded vs. constant knowledge of results on the
acquisition, retention, and transfer of a skilled walking task. _Human Movement
Science_. → Faded support outperforms constant support on retention and
transfer. Direct support for the guidance ladder being a ladder.

**[Czyz2024]** Czyż, S. H., Wójcik, A., & Solarská, P. (2024). Contextual
interference: A systematic review and meta-analysis. _Frontiers in Psychology_.
<https://doi.org/10.3389/fpsyg.2024.1377122> → Interleaving costs practice
performance and benefits retention. Why the diversity term exists and why
repeated identical repetition is discouraged.

**[CarterGrahn2016]** Carter, C. E., & Grahn, J. A. (2016). Optimizing music
learning: Exploring how blocked and interleaved practice schedules affect
advanced performance. _Frontiers in Psychology_.
<https://doi.org/10.3389/fpsyg.2016.01251> → The same effect measured in music
practice specifically, which is the domain KeyRecall is in.

**[YeganehDoost2017]** Yeganeh Doost, M., Orban de Xivry, J.-J., Bihin, B., &
Vandermeeren, Y. (2017). Two processes in early bimanual motor skill learning.
_Frontiers in Human Neuroscience_, 11:618.
<https://doi.org/10.3389/fnhum.2017.00618> → Bimanual learning is not the sum of
two unimanual skills. Why hands-together coordination is its own competency and
its own prediction channel.

**[Yokoi2016]** Yokoi, A., Bai, W., & Diedrichsen, J. (2016). Restricted
transfer of learning between unimanual and bimanual finger sequences. _Journal
of Neurophysiology_. <https://doi.org/10.1152/jn.00387.2016> → The transfer is
real but partial, which is what bounds `rhoHand` rather than sharing one
execution state.

**[HayashiNozaki2016]** Hayashi, T., & Nozaki, D. (2016). Improving a bimanual
motor skill through unimanual training. _Frontiers in Integrative Neuroscience_,
10:25. <https://doi.org/10.3389/fnint.2016.00025> → Single-hand work does
prepare hands-together work. The evidence behind coordination readiness being
recorded from single-hand attempts.

**[Panzer2009]** Panzer, S., Krueger, M., Muehlbauer, T., Kovacs, A. J., & Shea,
C. H. (2009). Inter-manual transfer and practice.
<https://pubmed.ncbi.nlm.nih.gov/19073469/> → Effector-specific and
effector-independent components of a motor representation. Why hand execution is
tracked per hand with bounded borrowing.

**[Wiestler2014]** Wiestler, T., Waters-Metenier, S., & Diedrichsen, J. (2014).
Effector-independent motor sequence representations exist in extrinsic and
intrinsic reference frames. <https://pubmed.ncbi.nlm.nih.gov/24695723/> → The
shared component is real, which is what justifies borrowing at all.

**[Temprado2002]** Temprado, J. J., Monno, A., Zanone, P. G., & Kelso, J. A. S.
(2002). Attentional demands reflect learning-induced alterations of bimanual
coordination dynamics. _European Journal of Neuroscience_, 16(7). → Coordination
cost falls with learning, which is why coordination is a state that moves rather
than a fixed property of an exercise.

**[Franz2001]** Franz, E. A., Zelaznik, H. N., Swinnen, S., & Walter, C. (2001).
Spatial conceptual influences on the coordination of bimanual actions: When a
dual task becomes a single task. _Journal of Motor Behavior_, 33(1). → Mirrored,
homologous movement is easier to coordinate than non-homologous movement. The
evidence behind introducing hands-together work through contrary motion.

## Music pedagogy and piano technique

**[Clark_PianoBasics]** Clark, M. _Piano Basics_. Baylor University Libraries.
<https://openbooks.library.baylor.edu/pianobasics/> → Primary source for
conventional major-scale fingering and for black-key harmonic minor. Its
multi-octave keyboard diagrams are direct evidence for internal continuation
rather than an inferred pattern.

**[ClassPiano]** _Class Piano_. Indiana University Press.
<https://doi.org/10.2979/ClassPiano> → Institutional corroboration for standard
scale fingering, scale groups, minor forms, and the irregular cases.

**[Sifter]** Sifter, S. _A Modern Method for Piano Scales_. Berklee Press.
<https://berkleepress.com/berklee-authors/suzanna-sifter/> → Preferred primary
direction for fixed-form melodic-minor fingering.

**[BrownLee2026]** Brown, M., & Lee, J. (2026). _Music Theory Online_, 32(2).
<https://www.mtosmt.org/issues/mto.26.32.2/mto.26.32.2.brown_lee.pdf> →
Peer-reviewed historical support for the C-sharp and F-sharp right-hand
melodic-minor exception in Hanon's scale pedagogy. The strongest evidence behind
the one fingering case that took real work to settle.

**[Funnell_Schotte]** Funnell, J. Discussion of the Schotte-revised Hanon
editions. <https://funnelljazz.eu/tag/melodic-minor/> → Documents the convention
that harmonic and melodic minor share fingering, with C-sharp and F-sharp as the
noted exceptions.

**[PDMPiano]** PDM Piano, technical curriculum.
<https://www.pdmpiano.org/epdm_p240_tech.html> → A university curriculum that
groups scales by fingering pattern, and independently separates C-sharp and
F-sharp melodic minor. Corroboration from a different tradition.

**[ABRSM2025]** ABRSM Piano Practical Grades syllabus, 2025 and 2026.
<https://www.abrsm.org/sites/default/files/2024-06/Piano%202025%20%26%202026%20Prac%20syllabus%2020240524_access.pdf>
→ Progression landmarks: when separate hands, two octaves, hands together, and
inversions conventionally appear. Used for the _shape_ of progression, never as
a threshold; see
[`decisions/curriculum-and-progression.md`](decisions/curriculum-and-progression.md)
for why grades are not admission bands.

**[RCM2022]** Royal Conservatory Piano Syllabus, 2022 Edition.
<https://teacherportal.rcmusic.com/getattachment/57f3734d-97e5-4777-b67e-4b1111ee31a3/piano-syllabus-2022-edition.pdf>
→ A second independent examination tradition, for corroboration where the two
agree and for caution where they do not.

**[Trinity2026]** Trinity Piano syllabus, online edition, February 2026.
<https://www.trinitycollege.com/resource?id=9079> → A third, same use.

**[StOlaf]** St. Olaf College Keyboard Proficiency Requirements, Level III.
<https://wp.stolaf.edu/music-handbook/files/2020/06/ProficiencyL3_052720.pdf> →
Institutional corroboration for arpeggio expectations outside the examination
boards.

**[Morin]** Morin, J. _Scale & Arpeggio Fingerings for Piano_.
<https://colorinmypiano.com/download/Scale__Arpeggio_Fingerings_for_Piano_2_Octave.pdf>
→ Specialist corroboration for two-octave arpeggio fingering.

**[Twedt]** Twedt, C. _Scale and Arpeggio Fingering Sheet_.
<https://blog.twedt.com/wp-content/uploads/2012/02/Scale-and-Arpeggio-Fingering.pdf>
→ The same, from a second specialist source.

**[Pang2023]** Pang, X., Zhao, Y., Wang, J., Wang, K., & Fang, Y. (2023). Piano
practice with emphasis on left hand for right handers. _Frontiers in
Psychology_. <https://doi.org/10.3389/fpsyg.2023.1124508> → Hand asymmetry in
piano practice is expected rather than pathological. Why an uneven pair of hands
is a normal state the scheduler must serve, not a defect to correct before
proceeding.

**[Chieffo2016]** Chieffo, R., et al. (2016). Motor cortical plasticity to
training started in childhood: The example of piano players. _PLOS ONE_.
<https://doi.org/10.1371/journal.pone.0157952> → Prior expertise changes the
acquisition curve, which is why placement seeds the prior and why advanced
players must be able to override it quickly.

**[Aiba2016]** Aiba, E., & Matsui, T. (2016). Music memory following short-term
practice and its relationship with the sight-reading abilities of professional
pianists. _Frontiers in Psychology_. <https://doi.org/10.3389/fpsyg.2016.00645>
→ Reading and remembering are separable in pianists. Supporting evidence for
treating a cued performance as no evidence about memory.

## Adaptive instruction and knowledge modeling

**[Pavlik2009]** Pavlik, P. I., Cen, H., & Koedinger, K. R. (2009). Performance
Factors Analysis: A new alternative to knowledge tracing. _AIED 2009_, 531-538.
<https://doi.org/10.3233/978-1-60750-028-5-531> → The logistic family, and
specifically that a task requiring several skills at once can be modeled without
a latent state per task. The general form KeyRecall's prediction channels
follow.

**[Choffin2019]** Choffin, B., Popineau, F., Bourda, Y., & Vie, J.-J. (2019).
DAS3H: Modeling student learning and forgetting for optimally scheduling
distributed practice of skills. <https://arxiv.org/abs/1905.06873> → The closest
conceptual match to KeyRecall: skills, items, and forgetting in one model.
Confirmation that combining a Q-matrix with time-sensitive memory is established
rather than novel.

**[Vie2019]** Vie, J.-J., & Kashima, H. Knowledge Tracing Machines.
<https://ojs.aaai.org/index.php/AAAI/article/view/3853/3731> (preprint:
<https://arxiv.org/abs/1811.03388>) → Item-level information adds predictive
value beyond skill-level effects. The precedent for `MaterialExecutionState`
existing at all.

**[LKT]** Logistic Knowledge Tracing, using student-, KC-, and item-level
features.
<https://jedm.educationaldatamining.org/index.php/JEDM/article/download/722/177>
→ Interpretable logistic models remain competitive with opaque ones, which is
why KeyRecall did not reach for a deep model it could not explain to a learner.

**[BKT]** Corbett, A. T., & Anderson, J. R. Bayesian Knowledge Tracing. → The
general architecture of hidden knowledge updated by evidence. Adopted in
structure; rejected in its binary mastery assumption, because MIDI performance
is not naturally binary.

## Assessment and measurement

**[Reckase2009]** Reckase, M. D. (2009). _Multidimensional Item Response
Theory_. Springer. <https://doi.org/10.1007/978-0-387-89976-3> → The
mathematical foundation for estimating several correlated abilities from one
observation, and for tracking uncertainty as a first-class quantity.

**[vanGroen2016]** van Groen, M. M., Eggen, T. J. H. M., & Veldkamp, B. P.
(2016). Multidimensional computerized adaptive testing for classifying
examinees. _Applied Psychological Measurement_.
<https://doi.org/10.1177/0146621616648931> → Adaptive item selection to reduce
uncertainty fastest. The basis for the information term, and for rejecting a
conventional placement exam in favor of adaptive placement.

**[DeBoeck2008]** De Boeck, P. (2008). Random item IRT models. _Psychometrika_.
<https://link.springer.com/article/10.1007/s11336-008-9092-x> → Established
precedent for treating item effects hierarchically with shrinkage, which is what
partial pooling in `MaterialExecutionState` approximates.

**[Baayen2008]** Baayen, R. H., Davidson, D. J., & Bates, D. M. (2008).
Mixed-effects modeling with crossed random effects for subjects and items.
<https://www.mpi.nl/publications/item60973/mixed-effects-modeling-crossed-random-effects-subjects-and-items>
→ Crossed learner and item effects are standard statistical practice, not an
exotic modeling choice.

**[Noortgate2003]** Van den Noortgate, W., De Boeck, P., & Meulders, M.
Cross-classified multilevel logistic models in psychometric response data.
<https://ppw.kuleuven.be/okp/_pdf/Noortgate2003CMLMI.pdf> → The same, in the
logistic setting KeyRecall actually uses.

**[MIRTExpansion]** Multidimensional and multivariate mixed-effects approaches
for expanding item-specific state.
<https://pmc.ncbi.nlm.nih.gov/articles/PMC5978597/> → The established path if a
single material residual later proves too parsimonious. Recorded as the
extension route rather than adopted now.

## Human-computer interaction

**[AdaptiveVisualGuidance2026]** _Adaptive Visual Hand Guidance for Piano
Training_ (2026). <https://arxiv.org/abs/2603.06253> → Adaptive visual guidance
improved subsequent unguided accuracy relative to static guidance. Encouraging
and domain-specific, but a short VR study rather than a longitudinal one, so it
supports the direction of the guidance ladder and does not set any of its
intervals.

## Privacy in learning analytics

**[LAPrivacy]** Work on synthetic learning-analytics data and differential
privacy for learning analytics. → Relevant to pooled collection and to shared
research datasets, and explicitly _not_ an argument for degrading a single
learner's own history on their own device. See
[`system/history.md`](system/history.md) for where each technique applies.
