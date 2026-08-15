import { describe, expect, it } from 'vitest'
import { areManagedInstanceEditFieldsAllowed, isManagedInstanceMutationAllowed, isManagedRouteAllowed } from './managedPolicy'

describe('managed launcher policy', () => {
  it('allows resource-pack and shader-pack mutations', () => {
    expect(isManagedInstanceMutationAllowed('resourcepacks/example.zip')).toBe(true)
    expect(isManagedInstanceMutationAllowed('shaderpacks/example.zip')).toBe(true)
  })

  it('rejects mods and protected instance mutations', () => {
    expect(isManagedInstanceMutationAllowed('mods/example.jar')).toBe(false)
    expect(isManagedInstanceMutationAllowed('instance.json')).toBe(false)
    expect(isManagedInstanceMutationAllowed('../mods/example.jar')).toBe(false)
  })

  it('allows only launcher routes used by the managed experience', () => {
    expect(isManagedRouteAllowed('/')).toBe(true)
    expect(isManagedRouteAllowed('/resourcepacks')).toBe(true)
    expect(isManagedRouteAllowed('/shaderpacks')).toBe(true)
    expect(isManagedRouteAllowed('/store')).toBe(false)
    expect(isManagedRouteAllowed('/mods')).toBe(false)
  })

  it('only allows launcher-local instance settings', () => {
    expect(areManagedInstanceEditFieldsAllowed(['instancePath', 'maxMemory', 'resolution', 'lastAccessDate'])).toBe(true)
    expect(areManagedInstanceEditFieldsAllowed(['instancePath', 'name'])).toBe(false)
    expect(areManagedInstanceEditFieldsAllowed(['instancePath', 'runtime'])).toBe(false)
    expect(areManagedInstanceEditFieldsAllowed(['instancePath', 'upstream'])).toBe(false)
  })
})
