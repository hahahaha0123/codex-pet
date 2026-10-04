# API 估算价格

核对日期：2026-10-03。货币为 USD，`api-prices.json` 的单位是每百万 tokens。金额为官方 API 文本 token 等价估算，不是订阅账户实际扣款，不含工具调用费用和区域附加费。历史使用量统一使用该价格快照，不重建历史促销价格。

| 模型 | 输入 | 缓存读 | 缓存写 | 输出 | 官方来源 |
|---|---:|---:|---:|---:|---|
| gpt-6.1-sol | 2 | 0.10 | 2.50 | 10 | https://developers.openai.com/api/docs/models/gpt-6.1-sol |
| gpt-6-astra | 10 | 1 | 12.50 | 50 | https://developers.openai.com/api/docs/models/gpt-6-astra |
| gpt-6-sol | 2 | 0.20 | 2.50 | 10 | https://developers.openai.com/api/docs/models/gpt-6-sol |
| gpt-6-luna | 0.10 | 0.01 | 0.125 | 0.50 | https://developers.openai.com/api/docs/models/gpt-6-luna |
| gpt-5.6-sol | 4 | 0.40 | 5 | 20 | https://developers.openai.com/api/docs/models/gpt-5.6-sol |
| gpt-5.6-terra | 2 | 0.20 | 2.50 | 12 | https://developers.openai.com/api/docs/models/gpt-5.6-terra |
| gpt-5.6-luna | 0.20 | 0.02 | 0.25 | 1.20 | https://developers.openai.com/api/docs/models/gpt-5.6-luna |
| gpt-5.5 | 5 | 0.50 | 不另加缓存写费 | 30 | https://developers.openai.com/api/docs/models/gpt-5.5 |

缓存读和缓存写是输入 tokens 的子集，计算时先从输入中扣除，避免重复计费。推理 tokens 已包含在输出中，不再单独加一次。累计 token_count 取增量，重复快照不重复累计，按最近 turn_context.model 归属到模型。

默认 Standard；日志明确记录 priority / fast 时乘 2，batch / flex 乘 0.5。日志没有服务层级时按 Standard 估算，不猜测应用实际账单。未知模型或无法识别的服务层级显示“价格未确认”；合计金额只合并已知部分并标注“已知部分”。长输入请求超过 272K 时，按日志 last_token_usage.input_tokens 判断，对该请求输入和缓存采用 2 倍、输出采用 1.5 倍估算。GPT-5.5 的按完整会话计费语义可能与本地逐请求近似不同，金额始终作为估算。

可根据后续官方价格变动修改 `api-prices.json`，需重启桌宠生效。
