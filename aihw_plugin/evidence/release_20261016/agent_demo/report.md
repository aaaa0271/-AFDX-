# AFDX AI 扩展调查报告

请求：分析复合故障并给出证据报告

案例：compound；来源：synthetic。
模型生成的受限任务：compound。

## 工具与证据

### language_plan

```json
{
  "status": "candidate",
  "plan": {
    "task": "compound",
    "tool": "diagnose_compound",
    "write": false
  },
  "generated_tokens": [
    "{",
    "\"task\"",
    ":",
    "\"compound\"",
    ",",
    "\"tool\"",
    ":",
    "\"diagnose_compound\"",
    ",",
    "\"write\"",
    ":",
    "false",
    "}",
    "<eos>"
  ],
  "decoder": "conditional autoregressive tanh RNN with finite grammar",
  "selection_reason": "trained_sequence_decoder",
  "sequence_share": 0.9955563154332939,
  "sequence_share_is_calibrated_probability": false,
  "general_chat_model": false
}
```

### retrieve_local_sources

```json
{
  "status": "ok",
  "citations": [
    {
      "file": "AI_USAGE.md",
      "line_start": 5,
      "line_end": 5,
      "text": "复合诊断可同时保留链路退化、双网内容分歧、时间异常、加载停滞、分片压力、管理突发和拥塞候选。测量相关性不直接证明物理原因，需要原始证据和干预实验核对。",
      "source_sha256": "d9f421db1e64f760f55469576efe14f83d9704bb29821053ea8242c27f2b4011",
      "similarity": 0.06026685982942581
    },
    {
      "file": "AI_USAGE.md",
      "line_start": 13,
      "line_end": 13,
      "text": "中文助手采用本地训练的微型条件循环语言模型，只生成有限的只读JSON工具计划。报告数字由工具计算，解释通过证据模板和本地文档检索完成，不具有通用问答或任意写设备配置能力。",
      "source_sha256": "d9f421db1e64f760f55469576efe14f83d9704bb29821053ea8242c27f2b4011",
      "similarity": 0.0437081940472126
    },
    {
      "file": "AFDX_INTERFACES.md",
      "line_start": 81,
      "line_end": 81,
      "text": "所有比例取0–1，其余精确边界见`afdx_ai/schema.py`。三个模型分别输出故障候选、异常分数、条件时延预测。森林投票份额不是经过校准的概率。直接同窗口证据可改变工具调查顺序，增加的优先级分数也不是后验概率。合成训练和异常召回限制见`UPSTREAM_MODEL_CARD.md`。",
      "source_sha256": "fe8d85da99d831ffe35a9b902de71ba957aae7adcd8282a5fbef6c9d99b5eca4",
      "similarity": 0.043369535356760025
    }
  ]
}
```

### temporal_and_compound

```json
{
  "schema": 1,
  "status": "candidate",
  "job_id": 1,
  "model_tag": "1a5cdc59",
  "source": "rtl_simulation",
  "errors": [],
  "unknown_error_bits": 0,
  "raw_logits_q": [
    -2070,
    -4431,
    -1942,
    1506,
    -3342,
    -1504,
    -3494,
    -110,
    210
  ],
  "cause_scores": {
    "congestion": 0.0003077430764601415,
    "link_degradation": 3.04069760233558e-08,
    "replica_divergence": 0.000507281282699237,
    "time_anomaly": 0.9972208094414864,
    "loader_stall": 2.1400322904809113e-06,
    "fragment_pressure": 0.0028009269671209736,
    "management_burst": 1.1818392082775557e-06
  },
  "compound_candidates": [
    {
      "cause": "time_anomaly",
      "score": 0.9972208094414864
    }
  ],
  "warning": false,
  "candidate_mask": 8,
  "future_queue_risk_score": 0.3942009561511044,
  "scores_are_calibrated_probabilities": false,
  "future_latency_max_p95_us": 867.2513486645405,
  "history_windows": 8,
  "horizon_windows": 3,
  "compute_cycles": 14035,
  "confirmed_physical_causes": [],
  "afdx_configuration_write": false,
  "hardware_timing_proof": false,
  "saturation_layers": 0,
  "rtl_log": "RESULT 1 1a5cdc59 0 0 14035 8 -2070 -4431 -1942 1506 -3342 -1504 -3494 -110 210",
  "measurement_source_declaration": "synthetic",
  "outside_features": [],
  "preprocessing_on_host": true
}
```

## 范围

模型分数和候选不等于已证实物理根因。所有计算来自实际工具输出；报告为模板渲染。
没有设备配置写入或板级验证。缺少仿真器时只记录测试计划，不把未执行实验计为通过。
