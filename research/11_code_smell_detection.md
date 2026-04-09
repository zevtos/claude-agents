# Code smell detection and refactoring: a comprehensive taxonomy

**The landscape of code smell detection spans four decades of research, from Fowler's 22 intuitive heuristics in 1999 to LLM-based detectors in 2025, yet fundamental disagreements persist on what constitutes a smell and how to detect one reliably.** Fowler's catalog remains the canonical reference, but Lanza & Marinescu formalized detection with metric-based strategies, Suryanarayana grounded smells in OO design principles, and Brown et al. extended the concept to architectural and organizational dysfunction. Tools like SonarQube and PMD now embed these ideas into CI/CD pipelines serving millions of developers, while machine learning approaches report F1 scores above 90% — though cross-project generalization remains weak and developer agreement on smell identification is surprisingly low. This report provides a unified reference across all major frameworks, concrete detection thresholds, tool capabilities, and the smell-to-refactoring mapping practitioners need.

---

## Fowler's catalog: 27 smells across two editions

Martin Fowler's *Refactoring* (1st edition 1999, 2nd edition 2018) defines the canonical code smell vocabulary. The first edition, co-authored with Kent Beck, identified **22 smells** in Java. The second edition, rewritten in JavaScript, revised the list to **24 smells** — adding four new smells (Mysterious Name, Global Data, Mutable Data, Loops), renaming several (Switch Statements → Repeated Switches, Lazy Class → Lazy Element, Inappropriate Intimacy → Insider Trading), and dropping three (Parallel Inheritance Hierarchies, Dead Code as a named smell, Incomplete Library Class). Across both editions, **27 unique smells** exist.

The five-category taxonomy widely associated with Fowler — Bloaters, Object-Orientation Abusers, Change Preventers, Dispensables, and Couplers — actually originates from community sources (notably refactoring.guru and Mäntylä et al.'s classification research), not from Fowler himself. Nevertheless, it provides a useful organizational framework:

**Bloaters** encompass smells where code entities have grown unwieldy: Long Method/Function (the most frequently cited smell, with Fowler suggesting even 10 lines warrants scrutiny), Large Class, Primitive Obsession (using primitives instead of small domain objects), Long Parameter List (more than 3–4 parameters), and Data Clumps (groups of variables that travel together). **Change Preventers** capture the pain of modification: Divergent Change (one class changed for multiple reasons) and Shotgun Surgery (one change scattered across many classes) are conceptual inverses. **Object-Orientation Abusers** include Repeated Switches (the 2nd edition's refinement focusing on *duplicated* conditional logic rather than any switch statement), Temporary Field, Refused Bequest, and Alternative Classes with Different Interfaces. **Dispensables** cover unnecessary elements: Duplicated Code (the "most pervasive smell" per Fowler), Lazy Element, Data Class, Speculative Generality, Dead Code, and Comments used as deodorant. **Couplers** address dependency problems: Feature Envy, Insider Trading, Message Chains, and Middle Man.

The 2nd edition's additions reflect modern concerns. **Global Data** targets mutable global state; **Mutable Data** reflects functional programming's influence, recommending Encapsulate Variable and Remove Setting Method. **Loops** explicitly favors collection pipelines (filter/map/reduce) over imperative iteration. **Mysterious Name** elevates naming to first-class smell status.

### The smell-to-refactoring mapping

Each smell has a primary remediation path through specific refactoring techniques. The table below captures the most important mappings:

| Smell | Primary refactorings | Composite approach |
|-------|---------------------|-------------------|
| Long Method/Function | Extract Function, Replace Temp with Query, Decompose Conditional | Often requires Introduce Parameter Object first, then repeated Extract Function |
| Large Class | Extract Class, Extract Superclass, Replace Type Code with Subclasses | Identify responsibility clusters, then Extract Class for each cluster |
| Primitive Obsession | Replace Primitive with Object, Replace Type Code with Subclasses | Extract Class → Move Function → Replace Conditional with Polymorphism |
| Long Parameter List | Replace Parameter with Query, Introduce Parameter Object, Preserve Whole Object | Introduce Parameter Object → then Extract Class if the object grows behavior |
| Data Clumps | Extract Class, Introduce Parameter Object | Extract Class for the clump → Preserve Whole Object at call sites |
| Repeated Switches | Replace Conditional with Polymorphism, Replace Type Code with Subclasses | Extract Function for the conditional → Replace Type Code → Replace Conditional |
| Feature Envy | Move Function, Extract Function | Extract the envious portion → Move to the target class |
| Divergent Change | Split Phase, Extract Class, Move Function | Identify axes of change → Extract Class per axis → Move Function to separate |
| Shotgun Surgery | Move Function/Field, Combine Functions into Class | Consolidate scattered logic → Inline Class if fragments are too small |
| Duplicated Code | Extract Function, Pull Up Method, Slide Statements | Slide Statements to align duplicates → Extract Function → Pull Up if in siblings |
| Data Class | Encapsulate Record, Move Function, Remove Setting Method | Encapsulate fields → identify operations that manipulate the data → Move Function into class |
| Message Chains | Hide Delegate, Extract Function | Extract Function to encapsulate the chain → consider if middle objects should Hide Delegate |
| Middle Man | Remove Middle Man, Inline Function | Remove Middle Man → clients talk directly to the real object |
| Global Data | Encapsulate Variable | Wrap in accessor functions → limit scope progressively |
| Mutable Data | Encapsulate Variable, Split Variable, Remove Setting Method | Encapsulate → Split Variable to separate usages → Replace Derived Variable with Query |

Composite refactorings — sequences of atomic refactorings applied together — are essential for complex smells. **God Class remediation**, for example, typically requires: (1) identify responsibility clusters via cohesion analysis, (2) Extract Class for each cluster, (3) Move Function/Field to the new classes, (4) possibly Extract Superclass if clusters share behavior. JDeodorant automates this composite sequence.

---

## Beyond Fowler: anti-patterns at the architectural scale

### Brown et al.'s AntiPatterns (1998)

Brown, Malveau, McCormick, and Mowbray's *AntiPatterns* operates at a higher level of abstraction, documenting **recurring problematic solutions** across software development, architecture, and project management. Unlike code smells (symptoms), anti-patterns describe the dysfunctional solutions themselves.

The **Blob (God Class)** is the flagship development anti-pattern: one class monopolizes processing while surrounding classes serve as data holders. Its refactored solution redistributes responsibilities through Extract Class and Move Method, applying the Single Responsibility Principle. **Lava Flow** captures dead code and forgotten design artifacts frozen in place — nobody removes them for fear of breaking things, typically caused by developer turnover and prototype-to-production transitions. **Spaghetti Code** describes systems without discernible structure, characterized by tangled control flow and no separation of concerns. **Functional Decomposition** results when non-OO developers work in OO languages, producing classes that each contain a single function with no inheritance or polymorphism. **Poltergeists** are ephemeral controller classes that briefly appear to invoke methods on other classes, then disappear — adding unnecessary abstraction. **Golden Hammer** describes the pathology of applying a familiar technology to every problem regardless of fit. **Cut-and-Paste Programming** — reuse through copying — leads to maintenance nightmares where bug fixes in one copy don't propagate.

At the architecture level, **Stovepipe System/Enterprise** captures ad hoc point-to-point integration creating brittle, non-interoperable subsystems. **Vendor Lock-In** documents the dependency trap where applications become inseparable from specific vendor products.

### Lanza & Marinescu's design disharmonies

Lanza and Marinescu's *Object-Oriented Metrics in Practice* (2006) bridges the gap between Fowler's informal heuristics and automated detection by defining **detection strategies** — composite logical rules built from metric thresholds derived statistically from **45 Java industrial projects**. Their 11 disharmonies fall into three categories:

**Identity disharmonies** affect individual entities in isolation: God Class, Feature Envy, Data Class, Brain Method, and Brain Class. **Collaboration disharmonies** address interaction patterns: Intensive Coupling (many calls concentrated in few classes), Dispersed Coupling (calls scattered across many classes), and Shotgun Surgery (being depended upon by many classes). **Classification disharmonies** target hierarchy problems: Refused Parent Bequest and Tradition Breaker.

Brain Method — a concept absent from Fowler — captures methods that centralize class intelligence: excessively long, highly complex, deeply nested, and using many variables. Brain Class extends this to classes containing multiple Brain Methods.

### Suryanarayana's principle-based taxonomy

Suryanarayana, Samarthyam, and Sharma's *Refactoring for Software Design Smells* (2014) collected **530+ documented smells** from the literature and organized **25 structural design smells** using the PHAME model, classifying each as a violation of Hierarchy, Abstraction, Modularization, or Encapsulation principles.

**Abstraction smells** (7 types) include Missing Abstraction (equivalent to Primitive Obsession), Multifaceted Abstraction (violating SRP — related to Large Class), and Unutilized Abstraction (the most abundant design smell in empirical studies — dead abstractions nobody uses). **Encapsulation smells** (4 types) range from Deficient Encapsulation (overly permissive accessibility) to Unexploited Encapsulation (using type checks instead of available polymorphism). **Modularization smells** (4 types) include Hub-Like Modularization (a class with excessive incoming and outgoing dependencies) and Cyclically-Dependent Modularization (circular dependencies preventing independent testing). **Hierarchy smells** (10 types) span from Missing Hierarchy to Cyclic Hierarchy, with Rebellious Hierarchy (subtypes that invalidate supertype contracts, violating LSP) being especially common in industrial software.

### How the frameworks relate

These four frameworks form a complementary ecosystem spanning granularity levels. Code smells are often **symptoms** of anti-patterns: multiple instances of Feature Envy, Large Class, and Long Method aggregate into the Blob anti-pattern. The Blob (Brown) maps to God Class (Lanza & Marinescu), which maps to Multifaceted Abstraction + Insufficient Modularization (Suryanarayana), which manifests as Large Class + Feature Envy + Data Class (Fowler). Spaghetti Code encompasses Brain Method, Intensive Coupling, Broken Modularization, and Long Method + Divergent Change + Shotgun Surgery. Poltergeists relate to Unnecessary Abstraction and Lazy Class. Cut-and-Paste Programming maps directly to Significant Duplication, Duplicate Abstraction, and Duplicated Code.

---

## Metrics, thresholds, and the detection strategy approach

### The core OO metrics for smell detection

Automated detection relies on a suite of well-established object-oriented metrics. **Size metrics** include LOC (Lines of Code), NOM (Number of Methods), and NOA (Number of Attributes). **Complexity metrics** center on WMC (Weighted Methods per Class — the sum of cyclomatic complexities of all methods) and McCabe's Cyclomatic Complexity per method. **ATFD** (Access to Foreign Data) counts attributes accessed from unrelated classes and is critical for detecting God Class and Feature Envy.

**Coupling metrics** include CBO (Coupling Between Objects — distinct classes a class is coupled to), RFC (Response For a Class — methods potentially executable in response to a message), and the Martin metrics Ce/Ca (efferent/afferent coupling at the package level). **Cohesion metrics** are the most contested: LCOM exists in at least five variants (LCOM1 through LCOM5), with LCOM1 (Chidamber & Kemerer's original) widely criticized as ill-formed. **TCC** (Tight Class Cohesion) — the ratio of method pairs sharing attribute access — is preferred by Lanza & Marinescu because it normalizes to [0,1] and has clearer semantics. **Inheritance metrics** include DIT (Depth of Inheritance Tree) and NOC (Number of Children).

### Lanza & Marinescu's threshold derivation

The key innovation of Lanza and Marinescu's approach is their **statistically-derived thresholds** from analyzing distributions across 45 Java projects. They define semantic labels with specific values:

- **Statistics-based**: LOW = μ − σ, AVERAGE = μ, HIGH = μ + σ, VERY HIGH = μ + 2σ
- **Generally-accepted meaning**: FEW = 2–5, SEVERAL = 2–5 (for nesting), MANY = 7–8 (Miller's memory capacity)
- **Common fractions**: ONE THIRD = 0.33, TWO THIRDS = 0.66, HALF = 0.5

Concrete derived values from their 45-system benchmark: **WMC VERY HIGH = 47**, **LOC HIGH (class) = 130**, **CYCLO HIGH (method) = 3.1**. The God Class detection strategy combines three conditions:

```
ATFD > 5  AND  WMC ≥ 47  AND  TCC < 0.33
```

This captures classes that access much foreign data, are very complex, and have low cohesion — the three hallmarks of a God Class. Feature Envy detection uses `ATFD > 5 AND LAA < 0.33 AND FDP ≤ 5`, identifying methods that use more foreign data than local, concentrated in few provider classes. Data Class detection examines `WOC < 0.33` (Weight of a Class — ratio of functional methods to all public members) combined with accessor counts and low complexity.

Brain Method detection — `LOC > 65 AND CYCLO ≥ 3.1 AND MAXNESTING ≥ 3 AND NOAV > 7` — identifies methods that centralize intelligence through excessive size, complexity, nesting depth, and variable usage simultaneously.

### Threshold disagreements across sources

A persistent challenge is that **no consensus exists on threshold values**. The table below illustrates the variance:

| Smell/Metric | Fowler | Lanza/Marinescu | PMD default | SonarQube | Other sources |
|-------------|--------|-----------------|-------------|-----------|---------------|
| Long Method (LOC) | "a few lines" | LOC > 65 | ~100 | Cognitive Complexity > 15 | 30 (strict) to 100 (lenient) |
| Long Parameter List | > 3 | — | > 10 | Configurable | 3–5 commonly used |
| Large Class (LOC) | "too many instance variables" | LOC > 130, WMC ≥ 47 | ~1000 | — | 500–1000 |
| CBO | — | — | > 20 | — | > 14 (Sahraoui et al.) |
| Cyclomatic Complexity | — | HIGH = 3.1 per method | > 10 | Cognitive > 15 | > 10 (McCabe's original) |
| DIT | — | — | — | — | ≤ 5 (Microsoft), ≤ 8 (max) |

Lanza and Marinescu's approach assumes normal distributions, but software metrics typically follow **power-law or log-normal distributions** (Chidamber & Kemerer data, Ferreira et al., Oliveira et al.), which undermines the mean ± σ derivation method. Fontana et al. (2015) proposed benchmark-based threshold derivation from 74 systems in the Qualitas Corpus as a more principled alternative. Aniche et al. (SCAM 2016) demonstrated that **architectural role affects metric distributions** — Controller classes naturally have higher CBO while Entity classes have higher LCOM — suggesting global thresholds are inherently imprecise.

---

## Machine learning challenges the heuristic paradigm

### Traditional ML approaches

Since 2016, machine learning has been extensively applied to code smell detection. **Fontana et al. (2016)** conducted the landmark study: 16 ML algorithms across 4 smells (Data Class, Large Class, Feature Envy, Long Method) on 74 software systems with 1,986 manually validated samples. **J48 decision trees and Random Forest achieved the highest performance**, with F-measures above 90% in cross-validation. SVMs were consistently the worst performers. Azeem et al.'s 2019 systematic literature review confirmed JRip (rule-based learner) and Random Forest as the most effective classifiers across studies.

Most ML models use **standard OO metrics as features** — WMC, CBO, LCOM, LOC, DIT, RFC, and Cyclomatic Complexity appear most frequently. Some approaches incorporate process metrics (change frequency, code churn) or tokenized source code.

### Deep learning and LLMs enter the field

Recent work explores deep learning: Bi-LSTM and GRU networks with data balancing report **up to 98–100% accuracy** on Long Method detection, though these results warrant skepticism given dataset limitations. CodeBERT and GraphCodeBERT have been fine-tuned for smell detection, with GraphCodeBERT proving most effective for Complex Conditional smells and UnixCoder best for Complex Method detection.

LLM-based approaches emerged in 2024–2025. **iSMELL** (ASE 2024) assembles LLMs with expert toolsets for integrated detection and refactoring. Sadik et al. (2025) benchmarked GPT-4.0 against DeepSeek-V3 on multilingual datasets, finding GPT-4.0 more precise but costly, while DeepSeek-V3 offered cost-effective but less precise detection. For architectural smells, Gemini 1.5 Pro achieved **100% recall for Hub-like Dependency** but only **49% of explanations were judged satisfactory** — highlighting that LLMs can detect patterns without truly understanding them.

### Why skepticism is warranted

Several fundamental issues plague ML-based detection. **Data imbalance** is pervasive: smells typically affect less than 20% of code entities, skewing classifiers. **Circular labeling** occurs when datasets are labeled by tools rather than human experts — ML models trained on tool-labeled data merely learn to replicate tool behavior. **Cross-project generalization drops 10–30%** compared to within-project evaluation, raising questions about practical deployability.

Most critically, **developer agreement on smell identification is surprisingly low**. Hozano et al. (2018) studied 75 developers across 2,700+ evaluations on 15 smell types and found low agreement regardless of experience level. If human experts disagree on ground truth, training and evaluating ML models becomes fundamentally problematic. Sharma et al. (2023) proposed incorporating individual developer preferences via feedback loops, acknowledging that code smells are "inherently subjective in nature."

---

## Detection tools: what each catches and how

The tool ecosystem ranges from lightweight linters to enterprise platforms. **No single tool is comprehensive**, and studies consistently show they disagree more than practitioners expect.

**PMD** offers **400+ rules** across 16+ languages, with its Design category most relevant to code smells: GodClass (using Lanza & Marinescu's WMC + ATFD + TCC strategy), ExcessiveMethodLength (default ~100 lines), CyclomaticComplexity (default > 10), ExcessiveParameterList (default > 10), and CouplingBetweenObjects (default > 20). Its CPD module detects duplicated code via Rabin-Karp string matching. PMD is purely rule-based, operating on AST analysis with XPath queries. It excels at implementation-level smells but struggles with cross-class design smells like Feature Envy.

**SonarQube** is the most widely adopted platform, covering **30+ languages** with **276 code smell rules** for Java alone. Its key innovation is **Cognitive Complexity** (introduced by G. Ann Campbell), which weights nested structures more heavily than McCabe's Cyclomatic Complexity — a flat switch statement scores low despite high cyclomatic complexity because it remains easy to understand. Default threshold: **15 per function**. SonarQube tracks technical debt as remediation time (default cost: 30 minutes per LOC), producing a Maintainability Rating from A (≤ 5% debt ratio) through E (> 50%).

**DesigniteJava** (by Tushar Sharma) detects the broadest range: **46 smell types across three granularity levels** — 7 architecture smells, 18–20 design smells (based on Suryanarayana's taxonomy), and 9–10 implementation smells. It reports **93.6% true positive rate** for implementation smells and 92.9% for design smells. It is the only major tool that systematically covers architecture-level smells like Cyclic Dependency, Unstable Dependency, and Hub-Like Modularization.

**JDeodorant** is unique in that it **identifies smells AND suggests specific, applicable refactorings**. It detects 5 smell types — God Class (→ Extract Class), Long Method (→ Extract Method via program slicing), Feature Envy (→ Move Method), Type Checking (→ Replace Conditional with Polymorphism), and Duplicated Code (→ Extract Clone). Developed by Tsantalis and Chatzigeorgiou, it applies sophisticated algorithms like cohesion-based class extraction and block-based slicing. However, Paiva et al. (2017) found its precision ranges from **8–35%** depending on smell and system, and it is semi-deprecated as an Eclipse plugin.

**iPlasma and inFusion** implement Lanza and Marinescu's detection strategies directly. iPlasma (open-source) provides the Overview Pyramid for system-level metric visualization, while inFusion (commercial, now discontinued) detected 22 smells for Java, C, and C++. Their threshold calibration from 45 industrial projects remains the most rigorous statistical foundation in the field.

**CodeScene** takes a fundamentally different approach through **behavioral code analysis**: using Git history to identify hotspots (files with high change frequency AND complexity), temporal coupling (files that change together), and knowledge distribution. It detects 25+ code health indicators across 30+ languages and uniquely **prioritizes technical debt by organizational impact** — focusing on code developers actually work with most.

### Tools agree on what's clean, disagree on what's smelly

Paiva et al. (2017) compared inFusion, JDeodorant, PMD, and JSpIRIT, finding **83–98% overall agreement** — but this is inflated by true negatives. Tools agree primarily on what is *not* smelly. Recall ranged from **0% to 100%** and precision from **0% to 100%** depending on tool, smell, and system. Fontana et al. (2012) concluded that "different detectors for the same smell do not meaningfully agree in their answers." Tools using the same underlying detection strategy (e.g., Marinescu's metrics) agreed at 97–99%, while tools using different approaches showed much lower concordance. **Threshold sensitivity** is the primary driver of disagreement.

---

## Conclusion: what practitioners should take away

The field has matured from Fowler's intuitive heuristics to sophisticated metric-based detection strategies, ML classifiers, and LLM-powered analyzers, yet **the fundamental subjectivity of smell identification remains unresolved**. Lanza and Marinescu's detection strategies — particularly for God Class (ATFD > 5, WMC ≥ 47, TCC < 0.33) and Feature Envy (ATFD > 5, LAA < 0.33, FDP ≤ 5) — represent the most rigorous automated approach, but their thresholds assume statistical distributions that real software metrics don't follow. ML approaches achieve impressive within-project accuracy but generalize poorly; LLMs show promise for semantic understanding but lack consistency and explainability.

For practitioners, the optimal strategy is **complementary tool deployment**: SonarQube for broad CI/CD integration and cognitive complexity tracking, DesigniteJava for design and architecture-level analysis, and CodeScene for prioritizing debt by organizational impact. Thresholds should be calibrated to project context rather than accepted as universal constants — a class in a web controller naturally has different coupling characteristics than one in a domain model. Most importantly, automated detection should be treated as a **triage mechanism** that surfaces candidates for human judgment, not as a definitive oracle. The code smell concept's enduring value lies not in precise classification but in providing a shared vocabulary for discussing design quality — a vocabulary that now spans from Fowler's method-level intuitions through Suryanarayana's principle-based taxonomy to Brown's architectural anti-patterns.