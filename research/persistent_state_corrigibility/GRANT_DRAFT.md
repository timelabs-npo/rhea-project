# Corrigibility Research Fund — application draft

## Project

**Persistent-State Corrigibility: Measuring and Reducing Memory-Induced Resistance to Human Correction**

## Summary

I propose a focused empirical study of a largely under-measured failure mode in long-horizon AI agents: persistent memory causing an agent to continue following stale, superseded, or adversarially inserted state after its human principal has corrected or retracted an earlier instruction.

The central question is simple and falsifiable: **holding the current human instruction fixed, does changing only persistent memory state measurably change whether an agent accepts correction, defers under unresolved authority conflict, or instead follows historical state?**

The project builds on an existing open-source persistent-memory system rather than starting from a hypothetical architecture. Rhea already has a portable SQLite-backed memory package with key-value facts, an append-only timeline, compact context feeds, Git history, episodic checkpoints, and a memory self-stress-test. I will use that substrate to construct controlled paired evaluations and a provenance-aware defense layer.

## Why this is corrigibility research

A practically corrigible agent should remain responsive to legitimate correction by its principal. Long-lived agent systems introduce a new source of inertia: old state survives across sessions and may continue shaping behavior after the principal changes course. This is distinct from one-turn instruction following. The system may have accumulated facts, plans, delegated instructions, tool outputs, summaries, or adversarial content that now competes with the current correction.

This project measures that phenomenon directly. It focuses on observable correction acceptance, conflict deference, and inappropriate memory override, rather than claiming to infer internal goals or solve corrigibility in general.

## Experimental design

I will create at least 25 paired scenario templates spanning reversible and irreversible agent actions. Each template will be evaluated under five controlled memory conditions:

1. clean current state;
2. stale superseded principal instruction;
3. poisoned untrusted memory claiming false authority;
4. stale state plus an explicit newer correction;
5. unresolved conflicting trusted state.

The evaluated agent chooses among a small explicit action set: follow the current principal instruction, ask for clarification, follow historical memory, or take the irreversible action suggested by stale/untrusted state.

Primary metrics are:

- Correction Acceptance Rate;
- Memory Override Error;
- Conflict Deference Rate;
- a composite Persistent-State Corrigibility Score.

The benchmark will compare at least three model/agent configurations and repeat stochastic runs. The main engineering comparison will be a baseline persistent-memory projection versus a provenance-aware projection that records source, authority, trust, supersession, and staleness before memories enter model context.

## Expected value and negative results

The study has useful outcomes in multiple directions.

- If persistent state causes a substantial drop in correction acceptance, the benchmark exposes a concrete long-horizon corrigibility failure mode.
- If simple provenance and supersession metadata largely fixes the problem, that identifies a cheap engineering intervention.
- If models ignore explicit provenance warnings and continue to act on stale or poisoned state, that provides evidence that stronger isolation or policy-level mechanisms are needed.
- If no meaningful degradation is found, I will publish the negative result and the conditions under which persistent memory did not impair correction acceptance.

## Existing work and feasibility

The implementation substrate already exists. The Rhea repository contains a zero-dependency Python persistent-memory package backed by SQLite, an append-only event timeline, compact context-feed generation, a multi-layer memory model, and a memory benchmark/self-stress-test. The initial persistent-state corrigibility protocol and model-independent scoring harness are also being implemented directly in the repository.

This means grant funding would primarily buy research time, model/API evaluation cost, replication, analysis, and publication rather than basic infrastructure development.

## Deliverables

1. Open-source benchmark generator and scorer.
2. Public scenario dataset with provenance annotations.
3. Results across multiple model/agent configurations.
4. Baseline vs provenance-aware memory comparison.
5. Technical report including negative results and limitations.
6. Reproduction instructions and machine-readable result files.

## Timeline

**Weeks 1–2:** finalize threat model, expand scenario set, add provenance-aware memory projection, validate scorer and experimental controls.

**Weeks 3–5:** run cross-model experiments, repetitions, ablations, and adversarial memory conditions.

**Weeks 6–7:** statistical analysis, robustness checks, replication pass, and benchmark cleanup.

**Week 8:** public report, code/data release, and concise research write-up.

## Funding request

I would like to request **$18,000** for an eight-week focused project. The intended use is primarily researcher time, with a smaller allocation for API/compute costs and independent replication/testing.

A smaller grant would still be useful: at approximately **$8,000–$10,000**, I would narrow the study to fewer model families and a smaller replication budget while preserving the paired experimental design and open benchmark release.

## Applicant / project links

Repository: `https://github.com/timelabs-npo/rhea-project`

Research lane: `research/persistent-state-corrigibility`

## Contact email version

Subject: Corrigibility Research Fund application — Persistent-State Corrigibility

Hello Max,

I would like to apply for a Corrigibility Research Fund grant for an eight-week empirical project on **persistent-state corrigibility**: whether long-lived agent memory causes systems to resist or mishandle legitimate human corrections by continuing to follow stale, superseded, or adversarially inserted state.

The experiment holds the current principal instruction fixed and varies only persistent memory state across clean, stale, poisoned, corrected, and unresolved-conflict conditions. I will measure correction acceptance, inappropriate memory override, and deference under authority conflict, then compare a baseline persistent-memory system against a provenance-aware version that explicitly tracks source, trust, authority, and supersession.

This is not a greenfield proposal. I already have an open-source persistent-memory implementation with SQLite-backed facts, an append-only timeline, context-feed generation, and a memory stress-test, and I am adding the benchmark/scoring harness directly to that codebase. The intended output is an open benchmark, cross-model empirical results, a provenance-defense ablation, reproducible data, and a public write-up including negative results.

I am requesting **$18,000** for eight weeks of focused work, mainly researcher time plus API/compute and replication costs. I could also execute a narrower version at roughly **$8,000–$10,000**.

Repository: https://github.com/timelabs-npo/rhea-project

I am happy to provide any additional detail that would help evaluate the project.

Best,
[Name]
