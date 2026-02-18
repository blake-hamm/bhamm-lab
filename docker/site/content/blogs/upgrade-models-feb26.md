---
title: "Self-hosted AI Model Upgrade"
tags: ["llm", "ai", "homelab", "amd", "self-hosting", "rocm", "vulkan", "qwen", "kimi", "glm", "minimax", "open-source"]
categories: ["ai"]
date: 2026-02-17
description: "Testing the latest open-source LLMs on AMD hardware is a vibe."
author: ["Blake Hamm"]
---

In this blog, I test the latest open source models that fit on my [homelab](https://docs.bhamm-lab.com/). I record the latency and provide a 'Vibe Score' to see if they replace existing models.

### TL;DR

- **Best Generalist**: [Kimi Linear 48B Instruct](https://huggingface.co/bartowski/moonshotai_Kimi-Linear-48B-A3B-Instruct-GGUF) — fast, capable, and consistent across different tasks; [GLM 4.7 Flash REAP](https://huggingface.co/unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF) was the runner up
- **Best Coder**: [Qwen3 Coder Next](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF) — immediate replacement for my previous coding model; exceptional speed and quality
- **Unexpected Result**: Heavy quantization (Q2_K_XL) is viable for long running, background workflows; [MiniMax 2.5](https://huggingface.co/unsloth/MiniMax-M2.5-GGUF) and [GLM 4.7 REAP](https://huggingface.co/unsloth/GLM-4.7-REAP-218B-A32B-GGUF) surprised me, but are too slow for human-in-the-loop tasks
- **Hardware**: [2× AMD AI Max+ 395 (128GB unified memory each) + 1× AMD AI R9700 (32GB)](https://docs.bhamm-lab.com/ai/#hardware)
- **What's Next**: [`beyond-vibes`](https://github.com/blake-hamm/beyond-vibes) — AI evaluation pipeline for llama.cpp models


### Homelab Review

First, let me explain how I run a homelab that supports AI workloads; you can find more details [here](https://docs.bhamm-lab.com/ai/). Basically, I have two AMD AI Max+ 395 (strix halo) and one AMD AI R9700.

The AI Max+ provides 128GB of unified memory (allocatable as VRAM) so I can run two decent sized models (~30b-120b models). I have an [open ticket](https://github.com/blake-hamm/bhamm-lab/issues/82) to enable [llama.cpp rpc](https://github.com/ggml-org/llama.cpp/blob/master/tools/rpc/README.md) which will support larger models, but it's still a WIP... The R9700 is another solid system with 32GB of VRAM and I use it for smaller, embedding models. So, as of now, I have capacity to run three models at a time.

The models I test are dictated by my hardware. I've made an effort to avoid Nvidia because I believe in the underdog (and suffering apparently). Given these constraints, what am I actually trying to accomplish with local AI?

{{< figure src="/strix-halo-server.jpg" caption="Dual Framework Mainboards (AMD AI Max+ 395 - Strix Halo) in a 2u server rack case. 256GB of unified memory and a rats nest of cables; LFG!"  width="100%" >}}


### Why the upgrade?

Open source research on foundational models is rapidly evolving, with AI labs like [DeepSeek](https://www.deepseek.com/en/), [MiniMax](https://www.minimax.io/), [Z.AI](https://www.zhipuai.cn/en) and [Moonshot AI](https://www.moonshot.ai/) dropping some heat right before Chinese New Year. I stay up to date on these developments through communities like `LocalLLama` and `bycloud` on Discord and Reddit.

While I'm no AI researcher, as an AI/ML engineer and self-hoster, I need to understand model architectures at a high level, specifically their impact on quality, latency, and context length. This matters both for my homelab and production AI applications.


### Use Cases

In my day-to-day, I use the latest models from OpenAI, Anthropic, AWS and Google. These proprietary models are state of the art (SOTA), no cap. They can service almost any use case, given the right prompt and context.

In contrast, even with decent hardware and incredible research published, the use cases for running local models have their limitations... At the moment, I have tested local models in [Open WebUI](https://openwebui.com/), [Roo Code](https://roocode.com/) and [OpenCode](https://opencode.ai/docs/). I've had success with Open WebUI and would recommend it for local models. Roo Code and OpenCode are trickier and depending on the codebase and task, local models will struggle. Specifically, when context exceeds 20k, these models run at a snail's pace on my AMD hardware. I believe this can be solved with better context management and prompting, but I didn't make much progress with my first JavaScript project and VSCode plugin - [camber](https://github.com/blake-hamm/camber)...

I used to dismiss "this is the worst AI will ever be" as marketing fluff for AGI. But with local models, that cliché has never felt more accurate. So given these limitations and my daily dependence on cloud APIs, you might wonder why I bother with self-hosted AI at all.


### Ultimate goal

Well, I have faith that eventually, I will find an open source model that I can run locally and consistently use with Roo Code and OpenCode. I started using Open Router for my personal projects and found that Kimi K2.5 fits that bill; I would consider this the best open source model for my use case and almost on par with SOTA closed-source models (while being a fraction of the cost). Unfortunately, I can't fit this model on 128GB of VRAM...

In addition to replacing paid models, I want to see the benefits of the latest model architecture research in latency. Through self-hosting AI models, I learned how MoE architectures, attention mechanisms and quantization techniques impact performance. GPT-OSS 120b drove this home; its speed and capability made these architectural trade-offs tangible. Testing new models helps me understand how different LLM families and architectures affect resource usage and latency.

In production AI applications, closed-source models become deprecated and you are required to upgrade. One of the great things with local AI is you don't have to worry about models being removed. Regardless, in my experience, newer models tend to have better evaluations scores and overall better vibe. It's best practice to have a framework to validate AI quality and latency in case you find a faster, cheaper model with better outcomes.

I'm hopeful that this new round of open source models will be more intelligent and faster; only one way to find out... Before testing the new batch, let's review what I'm currently running.


### Baseline Vibe

Unfortunately, I don't have a formal eval process comparing models so the review is more of a 'vibe'. Also, I have monitoring and tracing configured on my AI gateway ([kube-ai-stack](https://github.com/blake-hamm/kube-ai-stack)), so I will be collecting data for a post-deployment evaluation.

First off, let's review the fully arbitrary 'Vibe Score' which is my personal feeling towards the model. Basically, I will send the same prompt in Roo Code and OpenWebUI and record the latency along with a 1-5 Vibe Score on quality. I'll base it off of how well it solves the problem, any failures it might encounter and overall how I like the response. To put it simply, a 5 means the model has either incredibly high quality results OR it runs quick and has sufficient results, but may need some direction and hand holding.

Also, I collected a one-time 'latency' metric. This is not a scientific average or anything of that nature. It is simply a record of the latency for the first response in my test query in Roo Code. This includes the coldstart time when scaling from zero which is highly correlated with model size. Here is the prompt provided in Roo Code for [my homelab project](https://github.com/blake-hamm/bhamm-lab):

> docker/ceph-cleanup/README.md:1-3
> ##### Ceph cleanup
> This python script will cleanup ceph orphaned data in the kubernetes pool. AKA: it deletes data that is not in the prod kubernetes cluster as pv or volume snapshots
>
> Write unit tests for this project. Use pytest.

I chose this prompt because I found LLMs do a great job writing unit tests. Also, this 'project' is one simple python script that cleans up orphaned [ceph](https://ceph.io/en/) data. Furthermore, it's part of a monorepo and because of how Roo sends prompts, the context starts out at 10k+, stressing the models a bit.

So, let's dive right into my review of the current models I have available:

| Model | Family | Primary use case | Features | Notes | Latency | Vibe Score |
|-|-|-|-|-|-|-|
| [Qwen/Qwen3-Embedding-8B-GGUF:F16](https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF) | Qwen | Embeddings (Roo Code and LiteLLM cache with [Qdrant](https://qdrant.tech/)) | Embedding Only, Text | At one point I tried a few embedding models like [Nomic Embed Code](https://huggingface.co/nomic-ai/nomic-embed-code) and [Mistral Instruct Embed](https://huggingface.co/intfloat/e5-mistral-7b-instruct), but I decided Qwen embed can do it all | NA | 5 |
| [ggml-org/Qwen3-32B-GGUF:F16](https://huggingface.co/Qwen/Qwen3-32B-GGUF) | Qwen | Rarely used in practice; in theory, a good base model for fine tuning which was my original purpose | Dense, Base Model | Being a dense model, this was a little too slow on my hardware | 4m 29s | 3 |
| [unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF:Q6_K_XL](https://huggingface.co/unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF) | Qwen | Quick chat queries; likely a good model for custom agent, but didn't test | MoE, Hybrid Attention, Instruct | Recently replaced [qwen3-vl-30b-a3b](https://huggingface.co/unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF); there wasn't a noticeable difference, but it appeared higher on benchmarks | 38.3s | 5 |
| [unsloth/Qwen3-Next-80B-A3B-Thinking-GGUF:Q6_K_XL](https://huggingface.co/unsloth/Qwen3-Next-80B-A3B-Thinking-GGUF) | Qwen | More complex chat and search queries | MoE, Hybrid Attention, Reasoning | Similar to above, it replaced the 30b thinking version; however, I noticed it thinks a bit too excessively | 2m 46s | 3 |
| [ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF](https://huggingface.co/ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF) | Qwen | Great with Roo Code for coding-specific tasks, less reliable for tool calls/agents | MoE, Coding, Instruct | Worked better with simpler tools/prompts in OpenCode, but struggled with the complexity of Roo Code | 49.8s | 4 |
| [unsloth/Seed-OSS-36B-Instruct-GGUF:Q8_K_XL](https://huggingface.co/unsloth/Seed-OSS-36B-Instruct-GGUF) | ByteDance | Best for its size with Roo Code; good balance of speed and quality | Dense, Reasoning, Instruct | Very impressed with this model; one of my top picks; recent versions of llama.cpp have degraded performance - I am still unsure which container to use | 2m 51s | 5 |
| [gghfez/gpt-oss-120b-Derestricted.MXFP4_MOE-gguf](https://huggingface.co/gghfez/gpt-oss-120b-Derestricted.MXFP4_MOE-gguf) | GPT | Excellent for chat and search tools | MoE, Reasoning, Instruct, Derestricted | This is the jailbroke version of gpt oss; TBH I didn't notice much of a difference | 1m | 5 |
| [unsloth/gemma-3-27b-it-GGUF:BF16](https://huggingface.co/unsloth/gemma-3-27b-it-GGUF) | Google | I've tested it with images, seemed okay; I really don't have a good use case | Vision, Reasoning, Instruct, Multimodal | This is a bit faster than the latency suggests when using for multimodal use cases; the model struggles in agentic coding | 6m 42s | 3 |
| [bartowski/cerebras_GLM-4.5-Air-REAP-82B-A12B-GGUF:Q4_K_L](https://huggingface.co/bartowski/cerebras_GLM-4.5-Air-REAP-82B-A12B-GGUF) | GLM | Excellent for agentic tasks, coding and more difficult problems; top tier with Roo Code | Reasoning, MoE, Instruct | Can be a bit slow with significant context | 3m 7s | 5 |
| [unsloth/GLM-4.5-Air-GGUF:Q4_K_XL](https://huggingface.co/unsloth/GLM-4.5-Air-GGUF) | GLM | Very similar to above model, but slightly slower | Reasoning, MoE, Instruct | Pretty slow | 3m 44s | 4 |
| [ggml-org/Llama-4-Scout-17B-16E-Instruct-GGUF:Q4_K_M](https://huggingface.co/ggml-org/Llama-4-Scout-17B-16E-Instruct-GGUF) | Llama | It works with images as well; don't have much of a use case | Vision, MoE, Instruct, Multimodal | At one point in time, I had quite a few llama 3 models; after adding qwen and glm models, the llama 3 models showed their age with poor latency and quality | 2m 5s | 2 |

Looking back at this, there are only a few five star models for my use cases. These include Qwen embed, Qwen instruct, Seed OSS, GPT-OSS and GLM-Air-REAP; I could probably cover all my use cases with these models. Many of the other models are complementary and serve different purposes. Gemma and Llama are multimodal so they stand out slightly in that sense. Qwen 32b is a dense, base model which would be ideal for fine-tuning, but I haven't gotten around to that.

That's the joy of self hosting! No worries if I have model parameters sitting around on my hard drive. Better to have them accessible and in my possession than not at all! With that baseline established, here's what I'm testing next and the new vibe check.


### New model Vibe

| Model | Family | Use Case | Features | Latency | Vibe Score |
|-|-|-|-|-|-|
| [unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF:BF16](https://huggingface.co/unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF) | Mistral | Agentic coding (Roo Code) | Vision, Reasoning, Code | 1m 27s | 3 |
| [unsloth/Devstral-2-123B-Instruct-2512-GGUF:Q5_K_XL](https://huggingface.co/unsloth/Devstral-2-123B-Instruct-2512-GGUF) | Mistral | Agentic coding (heavily quantized) | Vision, Reasoning, Code | 10m 15s | 2 |
| [unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF:BF16](https://huggingface.co/unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF) | GLM | General purpose, quick queries | MoE, Reasoning, Lightweight | 40s | 5 |
| [unsloth/GLM-4.7-Flash-GGUF:BF16](https://huggingface.co/unsloth/GLM-4.7-Flash-GGUF) | GLM | General purpose | MoE, Fast Inference | 1m 41s | 4 |
| [unsloth/GLM-4.7-REAP-218B-A32B-GGUF:Q2_K_XL](https://huggingface.co/unsloth/GLM-4.7-REAP-218B-A32B-GGUF) | GLM | Complex reasoning tasks | MoE, Reasoning, Large Scale | 3m 58s | 2 |
| [bartowski/stepfun-ai_Step-3.5-Flash-GGUF:Q3_K_XL](https://huggingface.co/bartowski/stepfun-ai_Step-3.5-Flash-GGUF) | Stepfun | Long context tasks | MoE, Reasoning, Long Context | 2m 47s | 2 |
| [unsloth/Qwen3-Coder-Next-GGUF:Q6_K_XL](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF) | Qwen | Coding tasks, tool use | MoE, Coding, Tool Use | 1m 31s | 5 |
| [unsloth/Nemotron-3-Nano-30B-A3B-GGUF:BF16](https://huggingface.co/unsloth/Nemotron-3-Nano-30B-A3B-GGUF) | NVIDIA | Function calling, general purpose | MoE, Efficient, Function Calling | 1m 22s | 4 |
| [unsloth/Kimi-Dev-72B-GGUF:Q8_K_XL](https://huggingface.co/unsloth/Kimi-Dev-72B-GGUF) | Moonshot | Coding, long context | Coding, Long Context | 11m 55s | 2 |
| [bartowski/moonshotai_Kimi-Linear-48B-A3B-Instruct-GGUF:Q8_0](https://huggingface.co/bartowski/moonshotai_Kimi-Linear-48B-A3B-Instruct-GGUF) | Moonshot | General purpose, daily driver | MoE, Linear Attention, Efficient | 1m 25s | 5 |
| [unsloth/MiniMax-M2.5-GGUF:Q2_K_XL](https://huggingface.co/unsloth/MiniMax-M2.5-GGUF) | MiniMax | Long context, research tasks | MoE, Long Context | 3m 24s | 3 |

A few models emerged as standouts. Kimi Linear proved to be a fantastic all-purpose model; it was fast, capable, and consistent across different tasks. Qwen Coder Next was incredible which is echoed by communities online; its coding capabilities and speed are exceptional and it has immediately become my go-to for AI-Assisted Development. GLM 4.7 Flash REAP also impressed with its speed and solid general performance, vibing similar to GPT OSS 120b, but faster. Nemotron also caught my attention with its impressive speed; I'm curious to see how it performs in more targeted agentic workflows. On the other hand, MiniMax and GLM 4.7 REAP were very high quality all-rounders but their high latency made them unusable in practice, likely due to their larger size. Devstral has some [known](https://huggingface.co/unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF/discussions/2) [issues](https://github.com/ggml-org/llama.cpp/issues/19647) with its chat template and proved inconsistent.

### Conclusion

This round of vibing transformed my model lineup, retiring my previous go-tos: Qwen Coder Instruct, Seed OSS and GLM Air in favor of these newer drops. Kimi Linear has become my daily driver for general tasks and Qwen Coder Next is a game-changer for coding. It's wild how good these open source models are getting; they're approaching the quality of the big proprietary ones.

The biggest surprise? Heavy quantization actually works. I used to avoid Q2_K and Q3_K quants, thinking they'd be garbage, but MiniMax and GLM 4.7 REAP at Q2_K_XL proved me wrong. They're very high quality, but noticeably slow. I can imagine leveraging them for background, research-focused tasks which is something [I have planned](https://github.com/blake-hamm/bhamm-lab/issues/87).

The pace of open source AI is insane right now. You have these small research teams with limited hardware dropping models that compete with (and sometimes beat) what billion-dollar companies are putting out. Meanwhile the industry is frothing at the mouth about AGI and valuations, but the real story is that a handful of dedicated researchers are just... giving away powerful AI for free!

While [Dario keeps promising SWEs will be obsolete in 6 months](https://www.reddit.com/r/singularity/comments/1j8q3qi/anthropic_ceo_dario_amodei_in_the_next_3_to_6/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button) and my dad reads the WSJ convinced there's no bubble, these labs are actually democratizing access. Self-hosting used to be about privacy or avoiding vendor lock-in, but now? It's becoming a real alternative to feeding the cloud monopoly. My dream is that soon, anyone can afford a little box under their desk running models that rival the APIs. No subscriptions, no rate limits, no data harvesting. Just you and your AI.

### What's next

Regardless of my strong opinions on local AI, my process for evaluating models is a mess. I'm manually downloading models, testing one or two quants if I'm feeling ambitious and patient enough, juggling different llama.cpp containers to compare Vulkan vs ROCm backends, checking Arize Phoenix for latency and giving an arbitrary 'vibe check'. It's tedious and gets in the way of actually *using* these models.

I'd love to test [all the different versions of kimi linear](https://huggingface.co/models?library=gguf&sort=downloads&search=kimi+linear), but it would take me another 3 days and would still be just a vibe (not the good kind).

I need to automate this properly; I want to systematically test different quantization levels, container images, and llama.cpp CLI args to figure out the sweet spot of quality vs speed for each model. Sort of like what I do in my day-to-day for production AI applications. Real benchmarks, not just vibes. Checkout my next project `beyond-vibes` [here](https://github.com/blake-hamm/beyond-vibes) to follow along.
