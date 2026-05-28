#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const endpoint = "https://api.openai.com/v1/responses";
const model = process.env.OPENAI_MODEL || "gpt-5.2";
const timeoutMs = Number(process.env.OPENAI_TIMEOUT_MS || 180_000);
const mode = process.argv.includes("--report") ? "report" : "minimal";

function readSchemeAPIKey() {
  const schemePath = path.resolve(
    "AdmissionCalculator.xcodeproj/xcshareddata/xcschemes/AdmissionCalculator.xcscheme",
  );
  if (!fs.existsSync(schemePath)) {
    return null;
  }
  const xml = fs.readFileSync(schemePath, "utf8");
  const envMatch = xml.match(/<EnvironmentVariable\b[\s\S]*?OPENAI_API_KEY[\s\S]*?>/);
  const valueMatch = envMatch?.[0]?.match(/\bvalue\s*=\s*"([^"]+)"/);
  return valueMatch?.[1]?.replaceAll("&quot;", "\"").replaceAll("&amp;", "&") ?? null;
}

function resolveAPIKey() {
  if (process.env.OPENAI_API_KEY) {
    return { key: process.env.OPENAI_API_KEY, source: "shell environment" };
  }
  const schemeKey = readSchemeAPIKey();
  if (schemeKey) {
    return { key: schemeKey, source: "local Xcode scheme" };
  }
  return { key: null, source: "missing" };
}

function promptForMode() {
  if (mode === "minimal") {
    return "用中文回复一句话：OpenAI Responses API 已连通。";
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

async function main() {
  const { key, source } = resolveAPIKey();
  if (!key) {
    console.error("OPENAI_API_KEY is not set in shell env or local Xcode scheme.");
    process.exit(2);
  }

  const started = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  const body = {
    model,
    instructions:
      "你是美国本科申请规划顾问，只解释离线概率引擎已经算出的结果。不得修改概率，不得承诺录取，用中文输出。",
    input: promptForMode(),
    reasoning: { effort: "low" },
    text: { verbosity: mode === "report" ? "high" : "low" },
  };

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    const text = await response.text();
    const elapsedMs = Date.now() - started;
    if (!response.ok) {
      console.log(JSON.stringify({
        ok: false,
        mode,
        model,
        keySource: source,
        status: response.status,
        elapsedMs,
        errorPreview: text.slice(0, 1000),
      }, null, 2));
      process.exit(1);
    }

    let output = "";
    try {
      const json = JSON.parse(text);
      output = json.output_text ??
        (json.output ?? [])
          .flatMap((item) => item.content ?? [])
          .map((content) => content.text ?? "")
          .filter(Boolean)
          .join("\n");
    } catch {
      output = text;
    }

    console.log(JSON.stringify({
      ok: true,
      mode,
      model,
      keySource: source,
      status: response.status,
      elapsedMs,
      outputLength: output.length,
      outputPreview: output.slice(0, 360),
    }, null, 2));
  } catch (error) {
    const elapsedMs = Date.now() - started;
    console.log(JSON.stringify({
      ok: false,
      mode,
      model,
      keySource: source,
      elapsedMs,
      errorName: error?.name,
      errorMessage: error?.message,
    }, null, 2));
    process.exit(1);
  } finally {
    clearTimeout(timer);
  }
}

main();
