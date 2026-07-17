import { getToken } from "./api";

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

/** agent_status SSE 事件（后端 agents/streaming.py 定义） */
export interface AgentStatusEvent {
  status: "thinking" | "tool_call" | "tool_result" | "error";
  content?: string;
  tool?: string;
  args?: Record<string, unknown>;
  result?: string;
}

/** 工具调用步骤（挂在页面消息对象上，仅会话内存活） */
export interface AgentStep {
  tool: string;
  args?: Record<string, unknown>;
  result: string | null;
  running: boolean;
  /** 是否展开原始返回 */
  open?: boolean;
}

/** 工具名 → 中文标签（与后端 6 个注册工具对应，未知名回退原名） */
export const AGENT_TOOL_LABELS: Record<string, string> = {
  query_health_records: "查询健康记录",
  get_latest_health_records: "获取最新记录",
  analyze_health_trend: "趋势分析",
  get_user_profile_summary: "读取健康画像",
  calculator: "计算",
  get_current_datetime: "获取时间",
};

export interface StreamCallbacks {
  /** agent_status event: thinking / tool_call / tool_result / error */
  onAgentStatus?: (ev: AgentStatusEvent) => void;
  /** called on every content delta */
  onChunk?: (delta: string) => void;
  /** called once the server tells us the persisted conversation id */
  onConversationId?: (id: string) => void;
  /** called once the server emits follow-up suggestions */
  onSuggestions?: (s: string[]) => void;
  /** done — full text and conversation id */
  onDone?: (full: string, conversationId?: string) => void;
  onError?: (err: unknown) => void;
}

/**
 * POST /api/consult/chat/stream with Bearer auth, parse SSE chunks.
 *
 * Backend frame format: `data: <json>\n\n`
 *   { content: "..." }                       — delta
 *   { conversation_id: "..." }               — emitted after persistence
 *   { suggestions: ["...", "..."] }          — follow-up questions
 *   { type: "agent_status", status, ... }     — agent tool activity
 *   [DONE]                                   — terminator
 */
export async function streamChat(
  messages: ChatMessage[],
  cb: StreamCallbacks,
  conversationId?: string,
  signal?: AbortSignal
): Promise<void> {
  const token = getToken();
  if (!token) {
    cb.onError?.(new Error("未登录"));
    return;
  }

  let full = "";
  let convoId: string | undefined = conversationId;

  try {
    const resp = await fetch("/api/consult/chat/stream", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
        Accept: "text/event-stream",
      },
      body: JSON.stringify({
        messages,
        stream: true,
        agent_mode: true, // Agent 模式默认全开，是否调工具由 AI 决定
        conversation_id: conversationId ?? null,
      }),
      signal,
    });

    if (!resp.ok) {
      const text = await resp.text().catch(() => `${resp.status}`);
      cb.onError?.(new Error(`HTTP ${resp.status}: ${text}`));
      return;
    }
    if (!resp.body) {
      cb.onError?.(new Error("response.body is null"));
      return;
    }

    const reader = resp.body.getReader();
    const decoder = new TextDecoder("utf-8");
    let buffer = "";

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      // SSE frames are separated by blank lines
      let idx: number;
      while ((idx = buffer.indexOf("\n\n")) !== -1) {
        const frame = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 2);

        // each frame may have one or more `data:` lines
        for (const line of frame.split("\n")) {
          if (!line.startsWith("data:")) continue;
          const payload = line.slice(5).trim();
          if (!payload) continue;

          if (payload === "[DONE]") {
            cb.onDone?.(full, convoId);
            return;
          }

          try {
            const obj = JSON.parse(payload);
            // agent_status 必须最先判断：thinking 事件也带 content 字段，
            // 落到下面的 content 分支会把思考文案拼进回答
            if (obj && obj.type === "agent_status") {
              cb.onAgentStatus?.(obj as AgentStatusEvent);
            } else if (typeof obj.content === "string") {
              full += obj.content;
              cb.onChunk?.(obj.content);
            } else if (typeof obj.conversation_id === "string") {
              convoId = obj.conversation_id;
              cb.onConversationId?.(obj.conversation_id);
            } else if (Array.isArray(obj.suggestions)) {
              cb.onSuggestions?.(obj.suggestions);
            }
          } catch {
            // malformed frame — skip silently
          }
        }
      }
    }

    cb.onDone?.(full, convoId);
  } catch (e) {
    if ((e as any)?.name === "AbortError") return;
    cb.onError?.(e);
  }
}
