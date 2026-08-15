import { z } from 'zod'

const ttssAssetUrl = z.url().refine((value) => {
  const url = new URL(value)
  return url.protocol === 'https:'
    && url.hostname === 'launcher.ttss4096.com'
    && url.pathname.startsWith('/releases/')
})

const ttssReleaseSchema = z.object({
  tag_name: z.string().regex(/^v\d+\.\d+\.\d+$/),
  body: z.string(),
  published_at: z.iso.datetime(),
  assets: z.array(z.object({
    name: z.string().min(1),
    browser_download_url: ttssAssetUrl,
  })).min(1),
})

export type TtssRelease = z.infer<typeof ttssReleaseSchema>

export function parseTtssRelease(input: unknown): TtssRelease {
  return ttssReleaseSchema.parse(input)
}
