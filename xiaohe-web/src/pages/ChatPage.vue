<script setup lang="ts">
import { computed, nextTick, onMounted, reactive, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "../stores/auth";
import { streamChat, AGENT_TOOL_LABELS, type AgentStep, type ChatMessage } from "../services/chat";
import { conv } from "../services/api";
import { renderMarkdown } from "../lib/markdown";
import AppNav from "../components/AppNav.vue";

interface UIMsg extends ChatMessage {
  id: number;
  /** content shown in DOM (lags behind fullContent during typewriter) */
  content: string;
  /** the real complete text accumulated from chunks */
  fullContent?: string;
  /** true while backend is still streaming chunks */
  receiving?: boolean;
  /** umbrella flag: receiving from net OR typewriter still catching up */
  streaming?: boolean;
  /** agent tool-call steps (session-only, not persisted) */
  steps?: AgentStep[];
  /** transient thinking hint from agent_status */
  thinkingText?: string;
  /** steps panel expanded after completion (during receiving it's always open) */
  stepsOpen?: boolean;
}

const router = useRouter();
const route = useRoute();
const store = useAuthStore();

const messages = ref<UIMsg[]>([]);
const input = ref("");
const conversationId = ref<string | null>(null);
const FALLBACK_WELCOME = [
  "最近老觉得累，怎么调？",
  "晚上失眠该怎么办？",
  "血压偏高吃什么好？",
];
const suggestions = ref<string[]>([...FALLBACK_WELCOME]);
const sending = ref(false);
const loadingHistory = ref(false);
const errorMsg = ref<string | null>(null);
const scroller = ref<HTMLElement | null>(null);
const textarea = ref<HTMLTextAreaElement | null>(null);

let abortCtrl: AbortController | null = null;
let idSeq = 0;
function nextId() { return ++idSeq; }

const toolLabel = (t: string) => AGENT_TOOL_LABELS[t] ?? t;

const greeting = computed(() => {
  const h = new Date().getHours();
  if (h < 6)  return "深夜了，还好吗";
  if (h < 11) return "早上好";
  if (h < 14) return "中午了，喝杯水吗";
  if (h < 18) return "下午了";
  if (h < 22) return "晚上好";
  return "夜深了，慢慢说";
});

const userName = computed(() => store.user?.nickname || store.user?.phone?.slice(-4) || "");
const hasMessages = computed(() => messages.value.length > 0);

async function scrollDown() {
  await nextTick();
  if (scroller.value) {
    scroller.value.scrollTo({ top: scroller.value.scrollHeight, behavior: "smooth" });
  }
}

/** Frame-paced scroll for typewriter (avoid 60fps smooth-scroll thrash). */
let lastScrollMs = 0;
function fastScroll() {
  const now = performance.now();
  if (now - lastScrollMs < 90) return;
  lastScrollMs = now;
  if (scroller.value) {
    scroller.value.scrollTop = scroller.value.scrollHeight;
  }
}

/**
 * Typewriter loop: every animation frame, move some characters from
 * `fullContent` into `content`. Step size scales with backlog so a big
 * backend burst still feels like steady typing without making the user
 * wait several seconds after the network is done.
 */
function startTypewriter(msg: UIMsg) {
  const tick = () => {
    if (!msg.streaming) return;
    const full = msg.fullContent ?? "";
    const remaining = full.length - msg.content.length;

    if (remaining <= 0) {
      if (!msg.receiving) {
        msg.streaming = false;
        sending.value = false;
        return;
      }
      // backend still producing — wait one frame and check again
      requestAnimationFrame(tick);
      return;
    }

    // base: 1 char/frame ≈ 60 chars/sec (comfortable "fast typing" pace).
    // Only accelerate if the backlog is large enough that the user would otherwise wait noticeably.
    let step = 1;
    if (remaining > 300)      step = 4;
    else if (remaining > 150) step = 2;

    msg.content = full.slice(0, msg.content.length + step);
    fastScroll();
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

function autoResize() {
  const el = textarea.value;
  if (!el) return;
  el.style.height = "auto";
  el.style.height = Math.min(el.scrollHeight, 200) + "px";
}

async function send(content?: string) {
  const text = (content ?? input.value).trim();
  if (!text || sending.value) return;
  errorMsg.value = null;

  const userMsg: UIMsg = { id: nextId(), role: "user", content: text };
  // ⚠️ reactive() wrap is required: closures (streamChat callbacks, typewriter
  // raf) hold a reference to this object and mutate its fields. A plain object
  // pushed into a ref<Array> is auto-deep-proxied on read but mutations to the
  // *original* don't trigger setters — so DOM wouldn't update mid-stream.
  const aiMsg = reactive<UIMsg>({
    id: nextId(),
    role: "assistant",
    content: "",
    fullContent: "",
    receiving: true,
    streaming: true,
    steps: [],
    thinkingText: "",
  });
  messages.value.push(userMsg, aiMsg);
  input.value = "";
  autoResize();
  suggestions.value = [];
  sending.value = true;
  scrollDown();

  // kick off the typewriter — it'll wait for fullContent to grow
  startTypewriter(aiMsg);

  abortCtrl?.abort();
  abortCtrl = new AbortController();

  const payload: ChatMessage[] = messages.value
    .filter((m) => m.id !== aiMsg.id)
    .map((m) => ({ role: m.role, content: m.content }));

  await streamChat(
    payload,
    {
      onAgentStatus: (ev) => {
        if (ev.status === "thinking") {
          aiMsg.thinkingText = ev.content || "";
        } else if (ev.status === "tool_call") {
          aiMsg.steps!.push({
            tool: ev.tool ?? "",
            args: ev.args,
            result: null,
            running: true,
          });
        } else if (ev.status === "tool_result") {
          // 闭合最后一个同名 running 步骤
          const steps = aiMsg.steps ?? [];
          for (let i = steps.length - 1; i >= 0; i--) {
            if (steps[i].running && steps[i].tool === ev.tool) {
              steps[i].result = ev.result ?? "";
              steps[i].running = false;
              break;
            }
          }
        } else if (ev.status === "error") {
          aiMsg.steps?.forEach((s) => (s.running = false));
          errorMsg.value = ev.content || "Agent 处理出错";
        }
      },
      onChunk: (delta) => {
        aiMsg.fullContent = (aiMsg.fullContent ?? "") + delta;
      },
      onConversationId: (id) => {
        conversationId.value = id;
      },
      onSuggestions: (s) => {
        suggestions.value = s.slice(0, 3);
      },
      onDone: () => {
        aiMsg.receiving = false;
        // typewriter loop will set streaming=false + sending=false once it catches up
      },
      onError: (e: any) => {
        aiMsg.receiving = false;
        aiMsg.streaming = false;
        sending.value = false;
        const errText = e?.message || String(e);
        if (!aiMsg.fullContent) {
          aiMsg.fullContent = `（这次没能回到你 — ${errText}）`;
          aiMsg.content = aiMsg.fullContent;
        }
        errorMsg.value = errText;
      },
    },
    conversationId.value ?? undefined,
    abortCtrl.signal
  );
}

function stop() {
  abortCtrl?.abort();
  abortCtrl = null;
  sending.value = false;
  const last = messages.value[messages.value.length - 1];
  if (last && last.role === "assistant") {
    last.receiving = false;
    // flush any buffered chars so the partial reply isn't lost mid-typewriter
    if (last.fullContent && last.content !== last.fullContent) {
      last.content = last.fullContent;
    }
    last.streaming = false;
  }
}

function newChat() {
  abortCtrl?.abort();
  messages.value = [];
  conversationId.value = null;
  suggestions.value = [...FALLBACK_WELCOME];
  sending.value = false;
  errorMsg.value = null;
  if (route.query.conversationId) {
    router.replace({ path: "/chat" });
  }
  // refresh personalized welcome chips for the new session
  void fetchWelcome();
}

async function fetchWelcome() {
  try {
    const s = await conv.welcomeSuggestions();
    if (Array.isArray(s) && s.length > 0) {
      suggestions.value = s.slice(0, 3);
    }
  } catch {
    // backend may be cold or user has no profile yet — silently keep fallback
  }
}

function onKey(e: KeyboardEvent) {
  if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
    e.preventDefault();
    send();
  }
}

async function loadConversation(id: string) {
  loadingHistory.value = true;
  errorMsg.value = null;
  try {
    const detail = await conv.get(id);
    messages.value = detail.messages.map((m) => ({
      id: nextId(),
      role: m.role,
      content: m.content,
    }));
    conversationId.value = detail.id;
    suggestions.value = [];
    scrollDown();
  } catch (e: any) {
    errorMsg.value = e?.response?.data?.detail || e?.message || "加载历史失败";
    // bad id — reset to a fresh chat
    router.replace({ path: "/chat" });
  } finally {
    loadingHistory.value = false;
  }
}

watch(
  () => route.query.conversationId,
  (id) => {
    if (typeof id === "string" && id && id !== conversationId.value) {
      loadConversation(id);
    } else if (!id && conversationId.value) {
      // navigated to /chat without query — start a fresh chat
      messages.value = [];
      conversationId.value = null;
      suggestions.value = [...FALLBACK_WELCOME];
      void fetchWelcome();
    }
  }
);

onMounted(() => {
  const qid = route.query.conversationId;
  if (typeof qid === "string" && qid) {
    loadConversation(qid);
  } else {
    textarea.value?.focus();
    void fetchWelcome();
  }
});
</script>

<template>
  <div class="chat-page">
    <div class="aura a1" aria-hidden="true"></div>
    <div class="aura a2" aria-hidden="true"></div>

    <AppNav>
      <template #extra>
        <span class="convo-id" v-if="conversationId" :title="conversationId">
          · 续聊 {{ conversationId.slice(0, 8) }}
        </span>
        <button class="nav-pill" @click="newChat" data-hover>开一段新的</button>
      </template>
    </AppNav>

    <main class="frame" ref="scroller">
      <div class="stream">
        <!-- welcome state -->
        <section v-if="!hasMessages" class="welcome">
          <div class="welcome-orb" aria-hidden="true"></div>
          <p class="eyebrow">{{ greeting }} · {{ userName }}</p>
          <h1 class="display display-l">
            今天<br />
            <em>感觉怎么样</em>
          </h1>
          <p class="muted lede">
            随便说说就好 —— 没睡好、肚子不舒服、最近压力大都行。<br />
            她会慢慢听。
          </p>
          <div class="quick" v-if="suggestions.length">
            <button
              v-for="s in suggestions"
              :key="s"
              class="quick-chip"
              @click="send(s)"
              data-hover
            >
              {{ s }}
            </button>
          </div>
        </section>

        <!-- conversation -->
        <article
          v-for="(m, i) in messages"
          :key="m.id"
          class="msg"
          :class="[
            m.role === 'user' ? 'msg-user' : 'msg-ai',
            { last: i === messages.length - 1 }
          ]"
          :style="{ '--rot': `${(m.id % 3 - 1) * 0.8}deg` }"
        >
          <span class="role">
            {{ m.role === "user" ? "你" : "小云" }}
            <span class="streaming" v-if="m.streaming">
              <i></i><i></i><i></i>
            </span>
          </span>
          <div class="content">
            <template v-if="m.role === 'assistant'">
              <!-- agent tool-call steps -->
              <div v-if="m.steps && m.steps.length" class="agent-steps">
                <button
                  v-if="!m.receiving"
                  class="steps-summary"
                  @click="m.stepsOpen = !m.stepsOpen"
                  data-hover
                >
                  ⚙ 已调用 {{ m.steps.length }} 个工具
                  <span class="chev">{{ m.stepsOpen ? "▴" : "▾" }}</span>
                </button>
                <span v-else class="steps-summary passive">⚙ 正在调用工具</span>
                <ul v-if="m.receiving || m.stepsOpen" class="steps-list">
                  <li v-for="(s, si) in m.steps" :key="si" class="step">
                    <button class="step-row" @click="s.open = !s.open" data-hover>
                      <span v-if="s.running" class="step-spin" aria-hidden="true"></span>
                      <span v-else class="step-check">✓</span>
                      <span class="step-label">{{ toolLabel(s.tool) }}</span>
                    </button>
                    <pre v-if="s.open && s.result" class="step-result">{{ s.result }}</pre>
                  </li>
                </ul>
              </div>
              <span v-if="!m.content && m.streaming" class="thinking italic-en">
                {{ m.thinkingText || "正在听你说的话…" }}
              </span>
              <template v-else>
                <span class="md" v-html="renderMarkdown(m.content)"></span><span v-if="m.streaming" class="caret">▍</span>
              </template>
            </template>
            <template v-else>{{ m.content }}</template>
          </div>
        </article>

        <!-- follow-up suggestions, appears under the last AI message -->
        <div v-if="hasMessages && suggestions.length && !sending" class="follow-up">
          <span class="follow-label">↳ 你可能还想问</span>
          <button
            v-for="s in suggestions"
            :key="s"
            class="quick-chip small"
            @click="send(s)"
            data-hover
          >
            {{ s }}
          </button>
        </div>

        <div class="frame-fade-bottom" aria-hidden="true"></div>
      </div>
    </main>

    <footer class="composer-bar">
      <div class="composer">
        <textarea
          ref="textarea"
          v-model="input"
          placeholder="今天哪里不舒服？或者想问点什么"
          rows="1"
          @input="autoResize"
          @keydown="onKey"
          :disabled="sending"
        ></textarea>

        <button
          v-if="!sending"
          class="send"
          :class="{ ready: input.trim().length > 0 }"
          @click="send()"
          :disabled="!input.trim()"
          data-hover
          aria-label="发送"
        >
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none">
            <path d="M4 12l16-8-6 16-2.5-7.5L4 12z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" />
          </svg>
        </button>

        <button v-else class="send stop" @click="stop" data-hover aria-label="停一下">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
            <rect x="6" y="6" width="12" height="12" rx="2" />
          </svg>
        </button>
      </div>
      <p class="hint italic-en">
        Enter 发送 · Shift + Enter 换行 · 你说的话都会被她慢慢记住
      </p>
    </footer>
  </div>
</template>

<style scoped>
.chat-page {
  position: relative;
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
  isolation: isolate;
}

.aura {
  position: absolute;
  pointer-events: none;
  filter: blur(80px);
  z-index: 0;
  animation: drift 24s ease-in-out infinite alternate;
}
.a1 {
  width: 38vmax; height: 38vmax;
  top: -14vmax; right: -10vmax;
  background: radial-gradient(closest-side, var(--apricot) 0%, transparent 70%);
  opacity: 0.45;
}
.a2 {
  width: 32vmax; height: 32vmax;
  bottom: -14vmax; left: -10vmax;
  background: radial-gradient(closest-side, var(--sage) 0%, transparent 70%);
  opacity: 0.45;
  animation-delay: -10s;
}

/* nav extras */
.convo-id {
  font-family: var(--font-mono);
  font-size: 0.78rem;
  color: var(--ink-quiet);
  letter-spacing: 0.05em;
}
.nav-pill {
  font-size: var(--t-small);
  color: var(--sage-deep);
  padding: 0.35rem 0.9rem;
  background: rgba(168, 216, 197, 0.18);
  border: 1px solid rgba(107, 143, 122, 0.3);
  border-radius: 999px;
  cursor: pointer;
  transition: all 0.4s cubic-bezier(0.22, 1, 0.36, 1);
}
.nav-pill:hover {
  background: var(--sage-deep);
  color: var(--bone);
  border-radius: var(--bubble-3);
  transform: translateY(-1px);
}

/* main scroller */
.frame {
  flex: 1;
  overflow-y: auto;
  position: relative;
  z-index: 5;
}

.stream {
  max-width: 48rem;
  margin: 0 auto;
  padding: 3rem clamp(1rem, 3vw, 2.5rem) 2rem;
  display: flex;
  flex-direction: column;
  gap: 1.6rem;
}

/* welcome */
.welcome {
  position: relative;
  padding: 3rem 0 2rem;
  max-width: 36rem;
}
.welcome-orb {
  position: absolute;
  top: -3rem; right: -3rem;
  width: 14rem; height: 14rem;
  background: radial-gradient(closest-side, var(--sage) 0%, var(--apricot) 70%, transparent 90%);
  border-radius: var(--bubble-1);
  filter: blur(20px);
  opacity: 0.5;
  animation: morph 18s ease-in-out infinite alternate;
  z-index: -1;
}
@keyframes morph {
  0%   { border-radius: var(--bubble-1); }
  33%  { border-radius: var(--bubble-2); }
  66%  { border-radius: var(--bubble-3); }
  100% { border-radius: var(--bubble-4); }
}

.welcome h1 {
  margin: 1rem 0 1.5rem;
}
.welcome h1 em {
  font-style: normal;
  font-variation-settings: 'opsz' 144, 'SOFT' 100, 'wght' 500;
  background: linear-gradient(120deg, var(--sage-deep), var(--apricot));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
.welcome .lede {
  font-size: 1.05rem;
  margin-bottom: 2rem;
}

.quick {
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
}

.quick-chip {
  padding: 0.6rem 1.1rem;
  background: rgba(168, 216, 197, 0.18);
  color: var(--sage-deep);
  border: 1px solid rgba(107, 143, 122, 0.3);
  border-radius: 999px;
  font-size: 0.9rem;
  font-family: var(--font-body);
  cursor: pointer;
  transition: all 0.4s cubic-bezier(0.22, 1, 0.36, 1);
}
.quick-chip:hover {
  background: var(--sage-deep);
  color: var(--bone);
  transform: translateY(-2px) rotate(-1deg);
  border-radius: var(--bubble-3);
}
.quick-chip.small {
  font-size: 0.82rem;
  padding: 0.4rem 0.85rem;
}

/* message bubbles */
.msg {
  position: relative;
  padding: 1.1rem 1.4rem 1.2rem;
  max-width: 80%;
  transform: rotate(var(--rot, 0deg));
  transition: transform 0.6s cubic-bezier(0.22, 1, 0.36, 1);
  animation: msg-in 0.7s cubic-bezier(0.22, 1, 0.36, 1) backwards;
}
@keyframes msg-in {
  0%   { opacity: 0; transform: translateY(14px) rotate(var(--rot, 0deg)); }
  100% { opacity: 1; transform: translateY(0)   rotate(var(--rot, 0deg)); }
}

.msg-user {
  align-self: flex-end;
  background: var(--bone-deep);
  border: 1px solid rgba(42, 61, 53, 0.06);
  border-radius: var(--bubble-2);
}
.msg-ai {
  align-self: flex-start;
  background:
    linear-gradient(140deg, rgba(255, 255, 255, 0.7), rgba(168, 216, 197, 0.18)),
    var(--bone);
  border: 1px solid rgba(107, 143, 122, 0.18);
  border-radius: var(--bubble-3);
  backdrop-filter: blur(6px);
}

.role {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: var(--t-micro);
  letter-spacing: 0.24em;
  text-transform: uppercase;
  color: var(--ink-quiet);
  margin-bottom: 0.5rem;
}

.content {
  font-size: 1.05rem;
  line-height: 1.7;
  color: var(--ink);
  word-break: break-word;
}
/* user text isn't markdown — preserve their literal newlines */
.msg-user .content { white-space: pre-wrap; }

.thinking {
  color: var(--ink-quiet);
}

/* agent tool-call steps */
.agent-steps {
  margin-bottom: 0.6rem;
  padding: 0.5rem 0.7rem;
  background: rgba(168, 216, 197, 0.14);
  border: 1px solid rgba(107, 143, 122, 0.16);
  border-radius: 0.8rem;
}
.steps-summary {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.78rem;
  letter-spacing: 0.06em;
  color: var(--ink-quiet);
  background: none;
  border: none;
  cursor: pointer;
  padding: 0;
}
.steps-summary.passive { cursor: default; }
.steps-summary .chev { font-size: 0.7rem; }
.steps-list {
  list-style: none;
  margin: 0.4rem 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}
.step-row {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  font-size: 0.85rem;
  color: var(--ink);
  background: none;
  border: none;
  cursor: pointer;
  padding: 0;
}
.step-check { color: var(--sage-deep); font-size: 0.8rem; }
.step-spin {
  width: 0.7rem; height: 0.7rem;
  border: 2px solid rgba(107, 143, 122, 0.25);
  border-top-color: var(--sage-deep);
  border-radius: 50%;
  animation: step-spin 0.8s linear infinite;
}
@keyframes step-spin { to { transform: rotate(360deg); } }
.step-result {
  margin: 0.3rem 0 0 1.15rem;
  padding: 0.5rem 0.7rem;
  font-family: var(--font-mono);
  font-size: 0.72rem;
  line-height: 1.6;
  color: var(--ink-quiet);
  background: rgba(255, 255, 255, 0.6);
  border-radius: 0.5rem;
  white-space: pre-wrap;
  word-break: break-word;
  max-height: 12rem;
  overflow-y: auto;
}

.caret {
  display: inline-block;
  margin-left: 1px;
  color: var(--sage-deep);
  animation: blink 1s steps(2) infinite;
}
@keyframes blink { 50% { opacity: 0; } }

.streaming {
  display: inline-flex;
  align-items: center;
  gap: 3px;
}
.streaming i {
  width: 3px; height: 9px;
  background: var(--sage-deep);
  border-radius: 2px;
  animation: pulse 1.2s ease-in-out infinite;
}
.streaming i:nth-child(2) { animation-delay: 0.15s; }
.streaming i:nth-child(3) { animation-delay: 0.30s; }
@keyframes pulse {
  0%, 100% { transform: scaleY(0.5); opacity: 0.5; }
  50%      { transform: scaleY(1);   opacity: 1; }
}

.follow-up {
  align-self: flex-start;
  max-width: 80%;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
  padding-left: 0.5rem;
  margin-top: -0.5rem;
}
.follow-label {
  width: 100%;
  font-size: var(--t-micro);
  letter-spacing: 0.22em;
  text-transform: uppercase;
  color: var(--ink-quiet);
  margin-bottom: 0.3rem;
}

.frame-fade-bottom {
  position: sticky;
  bottom: 0;
  height: 3rem;
  background: linear-gradient(to top, var(--bone), transparent);
  pointer-events: none;
  z-index: 1;
}

/* composer */
.composer-bar {
  position: relative;
  z-index: 10;
  padding: 1rem clamp(1rem, 3vw, 2rem) 1.5rem;
  background: linear-gradient(to top, var(--bone) 60%, transparent);
}

.composer {
  position: relative;
  max-width: 48rem;
  margin: 0 auto;
  display: flex;
  align-items: flex-end;
  gap: 0.6rem;
  padding: 0.7rem 0.8rem 0.7rem 1.2rem;
  background:
    linear-gradient(140deg, rgba(255, 255, 255, 0.85), rgba(168, 216, 197, 0.15)),
    var(--bone);
  border: 1px solid rgba(107, 143, 122, 0.25);
  border-radius: var(--bubble-2);
  box-shadow: var(--shadow-soft);
  backdrop-filter: blur(8px);
  transition: border-color 0.4s, border-radius 1.2s ease-in-out;
  animation: composer-breathe 14s ease-in-out infinite alternate;
}
@keyframes composer-breathe {
  0%   { border-radius: var(--bubble-2); }
  50%  { border-radius: var(--bubble-3); }
  100% { border-radius: var(--bubble-4); }
}
.composer:focus-within {
  border-color: var(--sage-deep);
}

.composer textarea {
  flex: 1;
  resize: none;
  background: transparent;
  border: none;
  outline: none;
  font-family: var(--font-body);
  font-size: 1.05rem;
  line-height: 1.55;
  color: var(--ink);
  padding: 0.4rem 0;
  max-height: 200px;
  overflow-y: auto;
}
.composer textarea::placeholder {
  color: var(--ink-quiet);
  font-style: italic;
}

.send {
  flex-shrink: 0;
  width: 2.6rem; height: 2.6rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--bubble-1);
  background: rgba(168, 216, 197, 0.3);
  color: var(--ink-quiet);
  cursor: pointer;
  transition: all 0.5s cubic-bezier(0.22, 1, 0.36, 1);
}
.send:disabled { cursor: not-allowed; }
.send.ready {
  background: linear-gradient(135deg, var(--sage) 0%, var(--apricot) 100%);
  color: var(--ink);
}
.send.ready:hover {
  transform: rotate(-8deg) scale(1.05);
  border-radius: var(--bubble-3);
}
.send.stop {
  background: rgba(232, 184, 176, 0.6);
  color: var(--ink);
}
.send.stop:hover {
  background: var(--rose);
  transform: scale(1.05);
}

.hint {
  text-align: center;
  font-size: var(--t-micro);
  color: var(--ink-quiet);
  margin-top: 0.6rem;
  letter-spacing: 0.05em;
}

@media (max-width: 700px) {
  .nav-right { gap: 0.7rem; font-size: 0.75rem; }
  .convo-id { display: none; }
  .msg { max-width: 95%; }
  .stream { padding: 1.5rem 0.8rem 1rem; }
}
</style>
