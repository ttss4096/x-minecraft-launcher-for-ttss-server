<template>
  <SettingCard :title="t('BaseSettingGeneral.title')" icon="badge">
    <template v-if="!isBedrock">
      <div class="base-setting-general__section-heading">
        <v-icon size="small" color="primary">flash_on</v-icon>
        <span>{{ t('setting.quickLaunchSettings') }}</span>
      </div>
      <SettingItemCheckbox
        v-model="hideLauncher"
        :title="t('instanceSetting.hideLauncher')"
      >
        <BaseSettingGlobalLabel
          :global="isGlobalHideLauncher"
          @clear="resetHideLauncher"
        />
      </SettingItemCheckbox>
      <v-divider class="my-2" />
      <SettingItemCheckbox
        v-model="showLog"
        :title="t('instanceSetting.showLog')"
      >
        <BaseSettingGlobalLabel
          :global="isGlobalShowLog"
          @clear="resetShowLog"
        />
      </SettingItemCheckbox>
    </template>
  </SettingCard>

  <SettingCard
    v-if="isThirdparty || isElyBy"
    :title="t('setting.authenticationSettings')"
    icon="security"
  >
    <SettingItemCheckbox
      v-if="isThirdparty"
      v-model="disableAuthlibInjector"
      :title="t('instanceSetting.disableAuthlibInjector')"
      :description="t('instanceSetting.disableAuthlibInjectorDescription')"
    >
      <BaseSettingGlobalLabel
        :global="isGlobalDisableAuthlibInjector"
        @clear="resetDisableAuthlibInjector"
      />
    </SettingItemCheckbox>
    <v-divider v-if="isThirdparty && isElyBy" class="my-2" />
    <SettingItemCheckbox
      v-if="isElyBy"
      v-model="disableElyByAuthlib"
      :title="t('instanceSetting.disableElyByAuthlib')"
      :description="t('instanceSetting.disableElyByAuthlibDescription')"
    >
      <BaseSettingGlobalLabel
        :global="isGlobalDisableElyByAuthlib"
        @clear="resetDisableElyByAuthlib"
      />
    </SettingItemCheckbox>
  </SettingCard>
</template>

<script lang=ts setup>
import SettingCard from '@/components/SettingCard.vue'
import SettingItemCheckbox from '@/components/SettingItemCheckbox.vue'
import { kInstance } from '@/composables/instance'
import { kInstanceLaunch } from '@/composables/instanceLaunch'
import { useGamepadAction } from '@/composables/gamepad'
import { kUserContext } from '@/composables/user'
import { injection } from '@/util/inject'
import { AUTHORITY_MICROSOFT } from '@xmcl/runtime-api'
import { InstanceEditInjectionKey } from '../composables/instanceEdit'
import BaseSettingGlobalLabel from '@/components/BaseSettingGlobalLabel.vue'

const {
  resetFastLaunch,
  isGlobalHideLauncher,
  hideLauncher,
  resetHideLauncher,
  isGlobalShowLog,
  showLog,
  resetShowLog,
  disableAuthlibInjector,
  disableElyByAuthlib,
  isGlobalDisableAuthlibInjector,
  isGlobalDisableElyByAuthlib,
  resetDisableAuthlibInjector,
  resetDisableElyByAuthlib,
} = injection(InstanceEditInjectionKey)
const { userProfile } = injection(kUserContext)
const { instance } = injection(kInstance)
const isBedrock = computed(() => instance.value.edition === 'bedrock')

const isThirdparty = computed(() => userProfile.value.authority !== AUTHORITY_MICROSOFT)
const isElyBy = computed(() => userProfile.value.authority.startsWith('https://authserver.ely.by'))

const { t } = useI18n()

import { useLaunchButton } from '@/composables/launchButton'

// Gamepad X on the base-setting general tab launches / cancels / stops the game.
const { text: launchText, onClick: onLaunchClick } = useLaunchButton()
useGamepadAction('X', {
  label: () => launchText.value,
  handler: () => onLaunchClick(),
})

</script>

<style scoped>
.base-setting-general__icon {
  background-color: rgba(var(--v-theme-on-surface), 0.06);
  transition: outline-color 0.15s ease;
  outline: 2px solid transparent;
}
.base-setting-general__icon:hover {
  outline-color: rgb(var(--v-theme-primary));
}
.base-setting-general__icon--empty {
  border: 1px dashed rgba(var(--v-theme-on-surface), 0.24);
}
.base-setting-general__section-heading {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 16px 0;
  font-size: 0.875rem;
  font-weight: 600;
  color: rgba(var(--v-theme-on-surface), 0.72);
}
</style>
