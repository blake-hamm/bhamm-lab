---
title: "February 2026 Local Model Vibe Check"
---


## Why the upgrade?

Open source research on foundational models is rapidly evolving thanks to AI labs like [DeepSeek](https://www.deepseek.com/en/), [MiniMax](https://www.minimax.io/), [Z.AI](https://www.zhipuai.cn/en) and [Moonshot AI](https://www.moonshot.ai/). Prior to the Chinese new year, these labs dropped a ton of new models. I'll be testing some of these in addition to other models on my radar since my last upgrade in October.

I stay up to date on the latest models from various Discord and Reddit communities like LocalLLama and bycloud. I am by no means an AI researcher, but as an AI/ML engineer and self-hoster, it's helpful to understand at a high level the different model architectures and their impacts on latency and context length. This is my primary concern, especially with the homelab, but also with production AI applications.


### Homelab Review

I run a homelab that supports AI workloads; you can find more info [here](https://docs.bhamm-lab.com/ai/). Basically, I have two AMD AI Max 395+ (strix halo) and one AMD AI R9700.

The AI Max provides 128gb of vram so I can run two decent sized models (~30b-120b models). I have an [open ticket](https://github.com/blake-hamm/bhamm-lab/issues/82) to enable lamma.cpp rpc so that I can run larger models, but it's still a WIP... The R9700 is another solid system with 32gb of vram and I use it for smaller, embedding models. So, as of now, I have capacity to run three models at a time.

The models I test are dictated by my hardware. I've made an effort to avoid Nvidia because I believe in the underdog (and suffering apparently).


### Use Cases

In my day-to-day as an AI/ML Engineer, I use the latest models from OpenAI, Anthropic, AWS and Google. Models like GPT 5.3 codex, Claude Opus 4.6, Nova Premiere and Gemini 3 are state of the art (SOTA) and they can service just about any use case with the right prompt and context.

In contrast, even with decent hardware and incredible research coming out, the use cases for running local models has it's limitations.. At the moment, I have tested local models in [Open WebUI](https://openwebui.com/) and [Roo Code](https://roocode.com/). I've had success with Open WebUI and would recommend it for local models. Roo Code is a bit picky and local models on my hardware runa t a snails pace when context exceeds 20k. I believe this can be solved with better and smarter context management and prompting, but I didn't make much progress with my [camber](https://github.com/blake-hamm/camber) project... I plan to try out [OpenCode](https://opencode.ai/docs/) at some point which might be better with context management in code projects.

I relate with the cliche 'This is the worst you will ever see AI'. Initially, this statement felt like a marketing jingle to sell you on artificial general intelligence (AGI). In reality, this is more true than ever with smaller models and local AI.


### Ultimate goal

So, why the upgrade?

Well, I have faith that eventually, I will find an open source model that I can run locally and consistently use with Roo Code. I started using Open Router for my personal projects and found that Kimi K2.5 fits that bill; I would consider this the best open source model for my use case and almost on par with SOTO, closed-source models (while being a fraction of the cost). Unfortunately, I can't fit this model on 128gb of vram...

In addition to replacing paid models, I want to see the benefits of the latest model architecture research in latency. Through the process of self hosting AI models, I learned about the impact of mixture of experts (MoE) architecture and attention mechanisms and was shocked to see the benefits when using GPT-OSS. Testing out new models will help me better understand the benefits of different model families and architectures, generally impacting resource usage and latency.

In production AI applications, models become deprecated and you will be required to upgrade. One of the great things with local AI is you don't have to worry about models being removed. However, in my experience, newer models tend to have better evaluations scores and it's good practice to continuously check as you may find a faster model with higher quality output.

I'm hopefully that this new round of open source models will be more intelligent and faster; only one way to find out...


## Baseline Vibe

Unfortunately, I don't have a formal eval process comparing models so the review is more of a 'vibe'. I just started on a project for a better and automated eval process. Also, I have Arise Pheonix configured with LiteLLM in my [kube-ai-stack](https://github.com/blake-hamm/kube-ai-stack) AI gateway, so I will be collecting data for a post-deployment evaluation.

First off, let's review the fully arbitrary 'Vibe Score' which is my personal account and feeling towards the model. Basically, I will send the same prompt in Roo Code and OpenWebUI and record the latency along with a 1-5 Vibe Score on quality. I'll base it off of how well it solves the problem, any failures it might encounter and overall how I like the response.

So, let's dive right into my review of the current models I have available:

| Model | Family | Primary use case | Features | Notes | Latency |Vibe Score |
|-|-|-|-|-|-|-|
| [Qwen/Qwen3-Embedding-8B-GGUF:F16](https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF) | Qwen | Embeddings (Roo Code and LiteLLM similarity with [Qdrant](https://qdrant.tech/)) | Embedding Only, Text | At one point I tried a few embedding models like [Nomic Embed Code](https://huggingface.co/nomic-ai/nomic-embed-code) and [Mistral Instruct Embed](https://huggingface.co/intfloat/e5-mistral-7b-instruct), but I decided qwen embed can do it all | | 5 |
|[ggml-org/Qwen3-32B-GGUF:F16](https://huggingface.co/Qwen/Qwen3-32B-GGUF) | Qwen | Rarely used in practice; in theory, a good base model for fine tuning which was my original purpose | Dense, Base Model | Being a dense model, this was a little to slow on my hardware | | 3 |
| [unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF:Q6_K_XL](https://huggingface.co/unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF) | Qwen | Quick chat queries; likely a good model for custom agent, but didn't test | MoE, Hybrid Attention, Instruct | Recently replaced [qwen3-vl-30b-a3b](https://huggingface.co/unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF); there wasn't a noticeable difference, but it appeared higher on benchmarks | | 5 |
| [unsloth/Qwen3-Next-80B-A3B-Thinking-GGUF:Q6_K_XL](https://huggingface.co/unsloth/Qwen3-Next-80B-A3B-Thinking-GGUF) | Qwen | More complex chat and search queries | MoE, Hybrid Attention, Reasoning | Similar to above, it replaced the 30b thinking version; however, I noticed it would excessively think | | 3 |
| [ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF](https://huggingface.co/ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF) | Qwen | Great with Roo Code for coding-specific tasks, less reliable for tool calls/agents | MoE, Coding, Instruct | Might've worked better with OpenCode, but struggled with the complexity of Roo Code | | 4 |
| [unsloth/Seed-OSS-36B-Instruct-GGUF:BF16](https://huggingface.co/unsloth/Seed-OSS-36B-Instruct-GGUF) | ByteDance | Best for it's size with Roo Code; good balance of speed and quality | Dense, Reasoning, Instruct | Very impressed with this model; one of my top picks | | 5 |
| [gghfez/gpt-oss-120b-Derestricted.MXFP4_MOE-gguf](https://huggingface.co/gghfez/gpt-oss-120b-Derestricted.MXFP4_MOE-gguf) | GPT | Excellent for chat and search tools | MoE, Reasoning, Instruct, Derestricted | This is the jailbroke version of gpt oss; TBH I didn't notice much of a difference | | 5 |
| [unsloth/gemma-3-27b-it-GGUF:BF16](https://huggingface.co/unsloth/gemma-3-27b-it-GGUF) | Google | I've tested it with images, seemed okay; I really don't have a good use case | Vision, Reasoning, Instruct, Multimodal | | | 3 |
| [bartowski/cerebras_GLM-4.5-Air-REAP-82B-A12B-GGUF:Q4_K_L](https://huggingface.co/bartowski/cerebras_GLM-4.5-Air-REAP-82B-A12B-GGUF) | GLM | Excellent for agentic tasks, coding and more difficult problems; top tier with Roo Code | Reasoning, MoE, Instruct | Can be a bit slow with significant context | | 5 |
| [unsloth/GLM-4.5-Air-GGUF:Q4_K_XL](https://huggingface.co/unsloth/GLM-4.5-Air-GGUF) | GLM | Very similar to above model, but slightly slower | Reasoning, MoE, Instruct | Pretty slow | | 4 |
| [ggml-org/Llama-4-Scout-17B-16E-Instruct-GGUF:Q4_K_M](https://huggingface.co/ggml-org/Llama-4-Scout-17B-16E-Instruct-GGUF) | Llama | It works with images as well; don't have much of a use case | Vision, MoE, Instruct, Multimodal | At one point in time, I had quite a few llama 3 models; after adding qwen and glm models, the llama 3 models showed their age with their latency and quality | | 3 |

Looking back at this, there are only a few five star models for my use cases. These include Qwen embed, Qwen instruct, Seed OSS, GPT-OSS and GLM-Air-REAP. In all reality, I could probably cover all my use cases with just Qwen embed, Seed OSS and GPT-OSS. Many of the other models are complementary and serve different purposes. Gemma and Llama are multimodal so they stand out slightly in that sense, but when playing around with them, I didn't notice a significant difference. Qwen 32b is a dense, base model which would be ideal for fine-tuning which I haven't gotten around to.

That's the joy of self hosting! No worries if I have model parameters sitting around on my hard drive. Better to have them accessible and in my possession than not at all!

## New model Vibe

Now, here are the results:
| Model | Family | Use Case | Features| Replacement Model | Latency | Vibe Score |
|-|-|-|-|-|-|-|
| [unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF:BF16](https://huggingface.co/unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF) | Mistral | Agentic coding (Roo Code) | Vision, Reasoning, Code | GLM Air 4.5, Seed OSS or Qwen Coder | | |
| [unsloth/Devstral-2-123B-Instruct-2512-GGUF:Q5_K_XL](https://huggingface.co/unsloth/Devstral-2-123B-Instruct-2512-GGUF) | Mistral | Same as above, but will have to use a heavily quantized version | Vision, Reasoning, Code | GLM Air 4.5, Seed OSS or Qwen Coder | | |
| [unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF:Q2_K_XL](https://huggingface.co/unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF) | GLM | | MoE, Reasoning, Lightweight | | | |
| [unsloth/GLM-4.7-Flash-GGUF:BF16](https://huggingface.co/unsloth/GLM-4.7-Flash-GGUF) | GLM | | MoE, Fast Inference | | | |
| [unsloth/GLM-4.7-REAP-218B-A32B-GGUF:BF16](https://huggingface.co/unsloth/GLM-4.7-REAP-218B-A32B-GGUF) | GLM | | MoE, Reasoning, Large Scale | | | |
| [bartowski/stepfun-ai_Step-3.5-Flash-GGUF:Q3_K_XL](https://huggingface.co/bartowski/stepfun-ai_Step-3.5-Flash-GGUF) | Stepfun | | MoE, Reasoning, Long Context | | | |
| [unsloth/Qwen3-Coder-Next-GGUF:Q6_K_XL](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF) | Qwen | | MoE, Coding, Tool Use | | | |
| [unsloth/Nemotron-3-Nano-30B-A3B-GGUF:BF16](https://huggingface.co/unsloth/Nemotron-3-Nano-30B-A3B-GGUF) | NVIDIA | | MoE, Efficient, Function Calling | | | |
| [unsloth/Kimi-Dev-72B-GGUF:Q8_K_XL](https://huggingface.co/unsloth/Kimi-Dev-72B-GGUF) | Moonshot | | Coding, Long Context | | | |
| [bartowski/moonshotai_Kimi-Linear-48B-A3B-Instruct-GGUF:Q8_0](https://huggingface.co/bartowski/moonshotai_Kimi-Linear-48B-A3B-Instruct-GGUF) | Moonshot | | MoE, Linear Attention, Efficient | | | |
| [unsloth/MiniMax-M2.5-GGUF:Q2_K_XL](https://huggingface.co/unsloth/MiniMax-M2.5-GGUF) | MiniMax | | MoE, Long Context | | | |

## Conclusion

First off, I have to admit, my 'Vibe Check' is terrible and must be improved.. Moving forward, evals need to be automated; I'd like to test different llama.cpp backends (Vulkan vs. Rocm) as well as different quants. I've made it a number one priority to build a more robust eval process and will plan on re-evaluating these models as well as providing more 'vibe-based' feedback after using them more in practice.

Next, I've always stayed away from highly quantized versions of larger models. That was a big mistake as proven by MiniMax and GLM 4.7. I need to make sure I consider larger models moving forward.

Finally, the pace is insane for these open source models, different architectures and vendor families; I cannot wait to continue testing out the latest open source models. There's no better way to pop a bubble than to prove a small team of dedicated researchers with limited hardware can release models better than billion-dollar valued companies...
