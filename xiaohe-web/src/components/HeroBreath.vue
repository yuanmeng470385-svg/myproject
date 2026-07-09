<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";

const root = ref<HTMLElement | null>(null);
const blob = ref<HTMLElement | null>(null);

let raf = 0;
let mx = 0, my = 0;  // mouse normalized -1..1
let cx = 0, cy = 0;  // current

function onMove(e: MouseEvent) {
  if (!root.value) return;
  const r = root.value.getBoundingClientRect();
  mx = ((e.clientX - r.left) / r.width  - 0.5) * 2;
  my = ((e.clientY - r.top)  / r.height - 0.5) * 2;
}

function tick() {
  cx += (mx - cx) * 0.06;
  cy += (my - cy) * 0.06;
  if (blob.value) {
    blob.value.style.setProperty("--mx", `${cx * 28}px`);
    blob.value.style.setProperty("--my", `${cy * 28}px`);
  }
  raf = requestAnimationFrame(tick);
}

onMounted(() => {
  window.addEventListener("mousemove", onMove, { passive: true });
  raf = requestAnimationFrame(tick);
});
onUnmounted(() => {
  cancelAnimationFrame(raf);
  window.removeEventListener("mousemove", onMove);
});
</script>

<template>
  <section ref="root" class="hero">
    <!-- ambient auras drifting behind everything -->
    <div class="aura aura-1" aria-hidden="true"></div>
    <div class="aura aura-2" aria-hidden="true"></div>
    <div class="aura aura-3" aria-hidden="true"></div>

    <!-- main breathing blob -->
    <div ref="blob" class="blob-wrap" aria-hidden="true">
      <div class="blob blob-back"></div>
      <div class="blob blob-mid"></div>
      <div class="blob blob-front"></div>
      <div class="blob-veil"></div>
    </div>

    <!-- content grid -->
    <div class="hero-grid">
      <div class="vertical-mark">
        <span class="vrl">草木知春 · 皮肤知冷暖</span>
      </div>

      <div class="hero-copy">
        <p class="eyebrow">No. 01 — A quiet AI for the body</p>

        <h1 class="display display-xl">
          <span class="word w1">健</span><span class="word w2">康</span><span class="word w3">小</span><span class="word w4">云</span>
        </h1>

        <p class="tagline italic-en">
          A quiet companion for your body. <br />
          She remembers, softly.
        </p>

        <p class="lead">
          不是冷冰冰的体检报告。<br />
          是一只懂你身体的、会慢慢变厚的云 ——<br />
          记得你昨晚没睡好，知道你下雨天膝盖会酸。
        </p>

        <div class="hero-meta">
          <div>
            <span class="meta-label">in your pocket</span>
            <span class="meta-value">文字 · 语音 · 视频通话</span>
          </div>
          <div>
            <span class="meta-label">runs on</span>
            <span class="meta-value">健康小云大模型</span>
          </div>
        </div>
      </div>
    </div>

    <!-- scroll hint -->
    <div class="scroll-hint" aria-hidden="true">
      <span class="dot">❀</span>
      <span class="hint-text">向下，慢慢看</span>
    </div>
  </section>
</template>

<style scoped>
.hero {
  position: relative;
  min-height: 100vh;
  padding: clamp(8rem, 14vh, 12rem) var(--gutter) 4rem;
  overflow: hidden;
  isolation: isolate;
}

/* ambient auras */
.aura-1 {
  width: 56vmax; height: 56vmax;
  top: -18vmax; right: -14vmax;
  background: radial-gradient(closest-side, var(--apricot) 0%, transparent 70%);
  opacity: 0.7;
}
.aura-2 {
  width: 44vmax; height: 44vmax;
  bottom: -14vmax; left: -10vmax;
  background: radial-gradient(closest-side, var(--sage) 0%, transparent 70%);
  opacity: 0.65;
  animation-delay: -8s;
}
.aura-3 {
  width: 24vmax; height: 24vmax;
  top: 30%; left: 38%;
  background: radial-gradient(closest-side, var(--cream) 0%, transparent 70%);
  opacity: 0.6;
  animation-delay: -14s;
}

/* main blob — three nested layers that breathe out of sync */
.blob-wrap {
  position: absolute;
  top: 50%;
  right: clamp(-12rem, -8vw, -4rem);
  transform: translateY(-50%) translate(var(--mx, 0), var(--my, 0));
  width: clamp(28rem, 56vw, 48rem);
  height: clamp(28rem, 56vw, 48rem);
  z-index: 0;
  pointer-events: none;
  transition: transform 1.4s cubic-bezier(0.22, 1, 0.36, 1);
}

.blob {
  position: absolute;
  inset: 0;
  border-radius: var(--bubble-1);
  will-change: border-radius, transform;
}

.blob-back {
  background:
    radial-gradient(ellipse at 30% 30%, rgba(244, 197, 176, 0.9) 0%, rgba(244, 197, 176, 0.45) 45%, transparent 70%);
  transform: scale(1.05) translate(-4%, -2%);
  filter: blur(12px);
  animation: morph 22s ease-in-out infinite alternate;
}

.blob-mid {
  background:
    radial-gradient(ellipse at 60% 50%, rgba(168, 216, 197, 0.95) 0%, rgba(168, 216, 197, 0.55) 50%, transparent 75%);
  animation: morph 18s ease-in-out infinite alternate-reverse;
  animation-delay: -3s;
  filter: blur(2px);
}

.blob-front {
  background:
    radial-gradient(ellipse at 35% 65%, rgba(245, 230, 201, 0.7) 0%, rgba(168, 216, 197, 0.35) 40%, transparent 70%);
  animation: morph 26s ease-in-out infinite alternate;
  animation-delay: -10s;
  transform: scale(0.78);
}

.blob-veil {
  position: absolute;
  inset: -10%;
  border-radius: 50%;
  background: radial-gradient(closest-side, transparent 55%, rgba(248, 244, 237, 0.0) 80%, rgba(248, 244, 237, 0.85) 100%);
  pointer-events: none;
}

@keyframes morph {
  0%   { border-radius: var(--bubble-1); transform: scale(1)    rotate(0deg);  }
  25%  { border-radius: var(--bubble-2); transform: scale(1.04) rotate(2deg);  }
  50%  { border-radius: var(--bubble-3); transform: scale(0.98) rotate(-1deg); }
  75%  { border-radius: var(--bubble-4); transform: scale(1.03) rotate(3deg);  }
  100% { border-radius: var(--bubble-1); transform: scale(1)    rotate(0deg);  }
}

/* content grid */
.hero-grid {
  position: relative;
  z-index: 2;
  display: grid;
  grid-template-columns: auto 1fr;
  gap: clamp(1rem, 4vw, 4rem);
  align-items: center;
  max-width: 1320px;
  margin-inline: auto;
  min-height: calc(100vh - 14rem);
}

.vertical-mark {
  align-self: center;
  display: flex;
  align-items: center;
  height: 18rem;
}

.hero-copy {
  max-width: 38rem;
}

.eyebrow {
  margin-bottom: 2rem;
}

/* the wordmark: each Chinese char staggered with subtle entrance */
h1.display-xl {
  display: flex;
  gap: 0.06em;
  margin-bottom: 1.5rem;
  font-variation-settings: 'opsz' 144, 'SOFT' 100, 'wght' 350;
}
.word {
  display: inline-block;
  animation: drop-in 1.6s cubic-bezier(0.22, 1, 0.36, 1) backwards;
  transform-origin: center bottom;
}
.w1 { animation-delay: 0.15s; }
.w2 { animation-delay: 0.30s; }
.w3 { animation-delay: 0.45s; }
.w4 { animation-delay: 0.60s; }

@keyframes drop-in {
  0%   { opacity: 0; transform: translateY(40px) scale(0.92) rotate(-3deg); }
  60%  { opacity: 1; transform: translateY(0)   scale(1.02) rotate(0deg);  }
  100% { opacity: 1; transform: translateY(0)   scale(1)    rotate(0deg);  }
}

.tagline {
  font-size: clamp(1.3rem, 2vw, 1.8rem);
  line-height: 1.35;
  margin-bottom: 2rem;
  animation: drop-in 1.6s cubic-bezier(0.22, 1, 0.36, 1) 0.9s backwards;
}

.lead {
  font-size: var(--t-body-l);
  line-height: 1.7;
  color: var(--ink-soft);
  margin-bottom: 3rem;
  max-width: 28rem;
  animation: drop-in 1.6s cubic-bezier(0.22, 1, 0.36, 1) 1.05s backwards;
}

.hero-meta {
  display: flex;
  gap: 3rem;
  flex-wrap: wrap;
  animation: drop-in 1.6s cubic-bezier(0.22, 1, 0.36, 1) 1.2s backwards;
}

.hero-meta > div {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}

.meta-label {
  font-size: var(--t-micro);
  letter-spacing: 0.24em;
  text-transform: uppercase;
  color: var(--ink-quiet);
}

.meta-value {
  font-family: var(--font-display);
  font-variation-settings: 'opsz' 24, 'SOFT' 60;
  font-size: 1rem;
  color: var(--ink);
}

/* scroll hint */
.scroll-hint {
  position: absolute;
  bottom: 2rem;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.7rem;
  z-index: 5;
}

.scroll-hint .dot {
  font-size: 1.2rem;
  color: var(--sage-deep);
  animation: float-down 3.6s ease-in-out infinite;
}

.scroll-hint .hint-text {
  font-size: var(--t-micro);
  letter-spacing: 0.34em;
  color: var(--ink-quiet);
}

@keyframes float-down {
  0%, 100% { transform: translateY(0)    rotate(0deg);   opacity: 0.6; }
  50%      { transform: translateY(14px) rotate(-12deg); opacity: 1; }
}

@media (max-width: 900px) {
  .hero-grid { grid-template-columns: 1fr; }
  .vertical-mark { display: none; }
  .blob-wrap {
    right: -30vw;
    top: 30%;
    opacity: 0.75;
  }
}
</style>
