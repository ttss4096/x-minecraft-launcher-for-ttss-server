import { describe, expect, it } from 'vitest'
import { getInstallTaskTranslationKeys } from './task'

describe('install task localization', () => {
  it('uses NeoForge labels for NeoForge tasks', () => {
    expect(getInstallTaskTranslationKeys('installNeoForge', 'forge.installer')).toEqual({
      name: 'installNeoForge.name',
      subtitle: 'installNeoForge.downloadInstaller',
    })
  })
})
