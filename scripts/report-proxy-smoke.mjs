#!/usr/bin/env node
import process from "node:process";

const endpoint = process.env.REPORT_PROXY_URL;
const timeoutMs = Number(process.env.REPORT_PROXY_TIMEOUT_MS || 180_000);
const mode = process.argv.includes("--report") ? "report" : "minimal";

function promptForMode() {
  if (mode === "minimal") {
    return "用中文回复一句话：报告生成代理已连通。";
  }

  return `
请生成一段精简版申请报告，必须用中文，不承诺录取，不修改以下概率。

已计算结果：
- 学生：中国国际申请者，AP 课程，计算机科学，RD。
- 已选学校：Boston University 单校概率 38%，Massachusetts Institute of Technology 单校概率 0%（硬门槛未满足：缺少 required English proof）。
- 全部已选至少一所：38%。
- 分档：BU 目标，MIT 阻断。
- 待补资料：TOEFL 或 IELTS；SAT/ACT 或 Test Optional 策略。

输出结构：
1. 执行摘要
2. 逐校概率与风险
3. 0-1 个月行动建议
`;
}

function transactionPayload() {
  if (process.env.REPORT_PROXY_TRANSACTION_JWS) {
    return {
      productID: process.env.REPORT_PRODUCT_ID || "admission_calculator_ai_report",
      transactionID: process.env.REPORT_PROXY_TRANSACTION_ID || "manual-smoke",
      originalTransactionID: process.env.REPORT_PROXY_ORIGINAL_TRANSACTION_ID || process.env.REPORT_PROXY_TRANSACTION_ID || "manual-smoke",
      signedTransactionInfo: process.env.REPORT_PROXY_TRANSACTION_JWS
    };
  }

  if (process.env.REPORT_PROXY_LOCAL_FAKE_TRANSACTION === "true") {
    return {
      productID: process.env.REPORT_PRODUCT_ID || "admission_calculator_ai_report",
      transactionID: `local-smoke-${Date.now()}`,
      originalTransactionID: `local-smoke-${Date.now()}`,
      signedTransactionInfo: "local-dev-only"
    };
  }

  console.error("Set REPORT_PROXY_TRANSACTION_JWS, or set REPORT_PROXY_LOCAL_FAKE_TRANSACTION=true with SKIP_APPLE_VERIFY_FOR_LOCAL_DEV=true on the local proxy.");
  process.exit(2);
}

async function main() {
  if (!endpoint) {
    console.error("REPORT_PROXY_URL is not set.");
    process.exit(2);
  }

  const started = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        clientRequestId: `smoke-${Date.now()}`,
        instructions:
          "你是美国本科申请规划顾问，只解释离线概率引擎已经算出的结果。不得修改概率，不得承诺录取，用中文输出。",
        input: promptForMode(),
        transaction: transactionPayload()
      }),
      signal: controller.signal
    });

    const text = await response.text();
    const elapsedMs = Date.now() - started;
    if (!response.ok) {
      console.log(JSON.stringify({
        ok: false,
        mode,
        status: response.status,
        elapsedMs,
        errorPreview: text.slice(0, 1000)
      }, null, 2));
      process.exit(1);
    }

    let output = "";
    try {
      const json = JSON.parse(text);
      output = json.reportText ?? "";
    } catch {
      output = text;
    }

    console.log(JSON.stringify({
      ok: true,
      mode,
      status: response.status,
      elapsedMs,
      outputLength: output.length,
      outputPreview: output.slice(0, 360)
    }, null, 2));
  } catch (error) {
    console.log(JSON.stringify({
      ok: false,
      mode,
      elapsedMs: Date.now() - started,
      errorName: error?.name,
      errorMessage: error?.message
    }, null, 2));
    process.exit(1);
  } finally {
    clearTimeout(timer);
  }
}

main();
