---
title: "Summit-Sim"
weight: 15
---

#### [summit-sim.bhamm-lab.com](https://summit-sim.bhamm-lab.com/) · [github.com/blake-hamm/summit-sim](https://github.com/blake-hamm/summit-sim) · [Weber State AI Hackathon](https://weber-state-ai-hackathon.devpost.com/)

**🏆 Finalist — Advanced Category**

An AI-powered wilderness rescue simulator for Wilderness First Responder (WFR) training, built over 2 weeks for the Weber State AI Hackathon. Uses multi-agent validation to generate medically accurate, interactive backcountry emergencies.

**Problem:** WFR training relies on expensive live-action roleplay or static paper scenarios. Students rarely get enough dynamic, unpredictable repetitions to build critical decision-making under pressure.

**Solution:** Summit-Sim provides infinite, medically accurate WFR scenarios through a dynamic AI game loop. Students use natural language to evaluate scenes, check vitals, and apply treatments. Every action is evaluated against a hidden medical "truth," evolving the patient state dynamically.

**Agent Architecture:** Four specialized PydanticAI agents — Generator (creates scenarios with strict visible/hidden information separation), Image Generator (produces unique atmospheric scene images), Action Responder (evaluates student actions, updates PAS scores), and Debrief (post-simulation analysis with clinical reasoning assessment).

**AI Workflows:** Two interconnected LangGraph graphs handle authoring (scenario generation, image creation, instructor review via human-in-the-loop interrupts) and simulation (continuous game loop with progressive information revelation, capped at 80% PAS milestone completion or max turns).

**Observability:** MLflow tracks all LLM spans, captures instructor feedback, and logs judge evaluations across structure, scoring, medical accuracy, and continuity. A GEPA optimization framework iteratively improves agent prompts from expert feedback.

**Deployment:** Containerized with Docker, deployed on Kubernetes via Harbor registry + DragonflyDB for state persistence, fronted by Cloudflare Tunnel.
