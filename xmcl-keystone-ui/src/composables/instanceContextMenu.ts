import { Ref } from 'vue'
import { ContextMenuItem } from './contextMenu'
import { Instance } from '@xmcl/instance'
import { useInjectSidebarSettings } from './sidebarSettings'

export function useInstanceContextMenuFunc() {
  const { t } = useI18n()
  const { pinnedInstances, showOnlyPinned } = useInjectSidebarSettings()

  return (inst?: Instance) => {
    if (!inst) return []
    const isPinned = pinnedInstances.value.includes(inst.path)
    const result: ContextMenuItem[] = [
      {
        text: isPinned ? t('sidebar.unpin') : t('sidebar.pin'),
        icon: 'push_pin',
        section: 'sidebar',
        onClick() {
          if (isPinned) {
            pinnedInstances.value = pinnedInstances.value.filter(p => p !== inst.path)
          } else {
            pinnedInstances.value = [...pinnedInstances.value, inst.path]
          }
        },
      },
      {
        text: t('setting.sidebarShowOnlyPinned'),
        icon: showOnlyPinned.value ? 'check_box' : 'check_box_outline_blank',
        section: 'sidebar',
        onClick() {
          showOnlyPinned.value = !showOnlyPinned.value
        },
      },
    ]
    return result
  }
}

export function useInstanceContextMenuItems(instance: Ref<Instance | undefined>) {
  const f = useInstanceContextMenuFunc()

  return () => {
    const inst = instance.value
    return f(inst)
  }
}
