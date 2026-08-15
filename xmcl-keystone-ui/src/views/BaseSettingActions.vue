<template>
  <div
    v-if="!isBedrock || bedrockStorage"
    v-roving-tabindex
    role="toolbar"
    aria-orientation="horizontal"
    :aria-label="t('baseSetting.title', 2)"
    class="grid xl:gap-4 gap-1 home-actions"
    :style="{
      'grid-template-columns': 'minmax(0, 1fr)',
    }"
  >
    <v-btn
      data-testid="base-setting-log-action"
      v-shared-tooltip.left="() => isBedrock ? t('instance.openLogFolder') : t('logsCrashes.title')"
      variant="text"
      icon
      :loading="isValidating || loadingBedrockStorage"
      @click="showLogs"
    >
      <v-icon> subtitles </v-icon>
    </v-btn>
  </div>
</template>

<script lang="ts" setup>
import { useService } from "@/composables";
import { kInstance } from "@/composables/instance";
import { kInstances } from "@/composables/instances";
import { vRovingTabindex } from "@/directives/rovingTabindex";
import { vSharedTooltip } from "@/directives/sharedTooltip";
import { injection } from "@/util/inject";
import {
  BaseServiceKey,
  BedrockServiceKey,
  BedrockStoragePaths,
} from "@xmcl/runtime-api";
import { useDialog } from "../composables/dialog";
import { isBedrockInstance } from "@xmcl/instance";

const { instance } = injection(kInstance);
const { isValidating } = injection(kInstances);
const isBedrock = computed(() => isBedrockInstance(instance.value));
const { openDirectory } = useService(BaseServiceKey);
const { getStoragePaths } = useService(BedrockServiceKey);
const { show: showLogDialog } = useDialog("log");
const { t } = useI18n();
const router = useRouter()

const bedrockStorage = ref<BedrockStoragePaths>();
const loadingBedrockStorage = ref(false);

watch(isBedrock, async (bedrock) => {
  bedrockStorage.value = undefined;
  if (!bedrock) return;
  loadingBedrockStorage.value = true;
  try {
    bedrockStorage.value = await getStoragePaths();
  } finally {
    loadingBedrockStorage.value = false;
  }
}, { immediate: true });

function showLogs() {
  if (isBedrock.value) {
    openDirectory(bedrockStorage.value!.logsPath);
    return;
  }
  showLogDialog();
}

</script>
<style scoped>
.compact {
  background: rgba(0, 0, 0, 0.5);
}
</style>
<style>
.home-actions .v-speed-dial__list {
  padding: 0.2rem;
  /* background-color: rgba(0, 0, 0); */
  /* border-radius: 0.6rem; */
}
</style>
