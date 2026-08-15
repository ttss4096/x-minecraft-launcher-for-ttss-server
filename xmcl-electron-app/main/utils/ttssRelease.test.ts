import { describe, expect, it } from 'vitest'
import { parseTtssRelease } from './ttssRelease'

const validRelease = {
  tag_name: 'v0.66.2',
  body: 'TTSS managed launcher release',
  published_at: '2026-08-15T14:00:00Z',
  assets: [
    {
      name: 'app-0.66.2-linux.asar',
      browser_download_url: 'https://launcher.ttss4096.com/releases/latest/xmcl/app-0.66.2-linux.asar',
    },
  ],
}

describe('parseTtssRelease', () => {
  it('returns a typed release when the download manifest is valid', () => {
    expect(parseTtssRelease(validRelease)).toEqual(validRelease)
  })

  it('rejects a release whose asset URL is not HTTPS', () => {
    expect(() => parseTtssRelease({
      ...validRelease,
      assets: [{ ...validRelease.assets[0], browser_download_url: 'http://launcher.ttss4096.com/app.asar' }],
    })).toThrow()
  })

  it('rejects a release whose asset URL is outside the TTSS download site', () => {
    expect(() => parseTtssRelease({
      ...validRelease,
      assets: [{ ...validRelease.assets[0], browser_download_url: 'https://example.com/releases/app.asar' }],
    })).toThrow()
  })
})
