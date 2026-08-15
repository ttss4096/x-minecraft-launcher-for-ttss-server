<template>
  <div
    class="header sticky max-w-full select-none transition-all px-2"
    :style="{
      '--app-bar-blur': blurAppBar + 'px',
    }"
    :class="{
      compact,
    }"
    @transitionstart="onTransitionStart"
    @transitionend="onTransitionEnd"
    @transitioncancel="onTransitionEnd"
    @wheel.stop
  >
    <div
      class="flex flex-col header-content"
      style="margin: auto"
    >
      <div
        class="header-primary-row align-center flex max-h-20 flex-1 flex-grow-0 items-baseline pl-6 pr-2 gap-1"
      >
        <span
          :style="{
            fontSize: headerFontSize
          }"
          class="home-title overflow-hidden overflow-ellipsis whitespace-nowrap transition-all"
        >{{ name || `Minecraft ${version.minecraft}` }}</span>
        <router-view name="route" />
        <div class="flex-grow" />
        <router-view name="actions" v-slot="{ Component }">
          <transition
            name="slide-x-transition"
            mode="out-in"
          >
            <component :is="Component" class="flex-shrink-0" />
          </transition>
        </router-view>
      </div>
      <router-view name="extensions" v-slot="{ Component }">
        <transition
          name="slide-y-reverse-transition"
          mode="out-in"
        >
          <component
            :is="Component"
            class="header-extension px-4"
            :class="{
              'mt-5': !compact,
              'mt-1': compact,
            }"
          />
        </transition>
      </router-view>
    </div>
  </div>
</template>

<script lang=ts setup>
import { kInstance } from '@/composables/instance'
import { kCompact } from '@/composables/scrollTop'
import { kTheme } from '@/composables/theme'
import { injection } from '@/util/inject'

const { name, runtime: version } = injection(kInstance)
const { blurAppBar } = injection(kTheme)
const { t } = useI18n()

const transitioning = ref(false)
provide('transitioning', transitioning)

const onTransitionStart = (e: TransitionEvent) => {
  if (e.propertyName !== 'transform') return
  transitioning.value = true
}
const onTransitionEnd = (e: TransitionEvent) => {
  if (e.propertyName !== 'transform') return
  transitioning.value = false
}

const compact = injection(kCompact)
const headerFontSize = computed(() => {
  if (compact.value) {
    return '1.35rem'
  }
  if (name.value && name.value.length > 30) {
    return '2rem'
  }
  return '2.425rem'
})

</script>
<style scoped>

.header {
  padding-top: 2.5rem;
}

/*
 * Faded backdrop so content scrolling underneath the sticky header is masked
 * instead of bleeding through the (otherwise transparent) header. The gradient
 * matches the global app-bar overlay color and lives in the header's own
 * stacking context (z-20), so it sits above the scrolling page content while
 * staying behind the header text (z-index: -1). The backdrop blur is masked
 * with the same gradient so it fades out smoothly instead of cutting off.
 */
.header::before {
  content: '';
  position: absolute;
  inset: 0;
  bottom: -70px;
  z-index: -1;
  pointer-events: none;
  background-image: linear-gradient(var(--app-bar-color, transparent), transparent);
  -webkit-backdrop-filter: blur(var(--app-bar-blur, 0));
  backdrop-filter: blur(var(--app-bar-blur, 0));
  -webkit-mask-image: linear-gradient(black 40%, transparent);
  mask-image: linear-gradient(black 40%, transparent);
}

.header.compact::before {
  bottom: -20px;
}

.header.compact {
  padding-top: 0.5rem;
  padding-bottom: 0.5rem;
}

.header-primary-row,
.home-title {
  min-width: 0;
}

.header.compact .header-primary-row {
  min-height: 36px;
  align-items: center;
  padding-left: 1rem;
}

@media (max-width: 900px) {
  .header {
    padding-right: 0.25rem !important;
    padding-left: 0.25rem !important;
  }

  .header-primary-row {
    padding-left: 0.75rem !important;
  }

  .header.compact .home-title {
    max-width: 40vw;
  }

  .header-extension {
    padding-right: 0.75rem !important;
    padding-left: 0.75rem !important;
  }
}

</style>
