import { describe, expect, it } from 'vitest'
import { isThirdPartyLoginAllowed } from './login'

describe('login authority availability', () => {
  it('keeps third-party and offline authorities available with zero accounts', () => {
    expect(isThirdPartyLoginAllowed()).toBe(true)
  })
})
