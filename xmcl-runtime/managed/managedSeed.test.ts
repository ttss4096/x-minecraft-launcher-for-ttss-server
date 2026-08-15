import { createHash, generateKeyPairSync, sign } from 'crypto'
import { mkdir, mkdtemp, readFile, writeFile } from 'fs/promises'
import { tmpdir } from 'os'
import { join } from 'path'
import { afterEach, describe, expect, it } from 'vitest'
import { ZipFile } from 'yazl'
import { installManagedSeed } from './managedSeed'

function sha256(data: Buffer): string {
  return createHash('sha256').update(data).digest('hex')
}

function finishZip(zip: ZipFile): Promise<Buffer> {
  zip.end()
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = []
    zip.outputStream.on('data', (chunk: Buffer) => chunks.push(chunk))
    zip.outputStream.on('end', () => resolve(Buffer.concat(chunks)))
    zip.outputStream.on('error', reject)
  })
}

async function createSeed(seedDirectory: string): Promise<void> {
  const files = new Map<string, Buffer>([
    ['instance.json', Buffer.from('{"name":"清汤闲水服务器"}')],
    ['mods/example.jar', Buffer.from('seed-mod')],
    ['resourcepacks/builtin.zip', Buffer.from('seed-resource-pack')],
  ])
  const zip = new ZipFile()
  for (const [path, content] of files) {
    zip.addBuffer(content, path, { mtime: new Date(315532800000) })
  }
  const payload = await finishZip(zip)
  const manifest = Buffer.from(JSON.stringify({
    schemaVersion: 1,
    packId: 'ttss-ciap-1.21.1',
    releaseId: 'ttss-test',
    contentDigest: sha256(Buffer.from('test-content')),
    payload: {
      file: 'ttss-client-seed.zip',
      sha256: sha256(payload),
    },
    versions: {
      minecraft: '1.21.1',
      neoforge: '21.1.236',
      automodpack: '4.0.6-ttss-managed.2',
    },
    mutableRoots: ['resourcepacks', 'shaderpacks', 'screenshots', 'logs'],
    files: [...files.entries()].map(([path, content]) => ({
      path,
      size: content.byteLength,
      sha256: sha256(content),
      mutable: path.startsWith('resourcepacks/') || path.startsWith('shaderpacks/'),
    })),
  }, null, 2))
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 })
  await mkdir(seedDirectory, { recursive: true })
  await Promise.all([
    writeFile(join(seedDirectory, 'ttss-client-seed.zip'), payload),
    writeFile(join(seedDirectory, 'ttss-client-seed.manifest.json'), manifest),
    writeFile(join(seedDirectory, 'ttss-client-seed.manifest.sig'), sign('sha256', manifest, privateKey)),
    writeFile(join(seedDirectory, 'ttss-client-seed.public.pem'), publicKey.export({ type: 'spki', format: 'pem' })),
  ])
}

describe('managed seed installer', () => {
  const roots: string[] = []

  afterEach(async () => {
    const { rm } = await import('fs/promises')
    await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })))
  })

  it('installs a signed seed once and then yields ownership to AutoModpack', async () => {
    const root = await mkdtemp(join(tmpdir(), 'xmcl-managed-seed-'))
    roots.push(root)
    const seedDirectory = join(root, 'seed')
    const instanceDirectory = join(root, 'game', 'instances', '清汤闲水服务器')
    await createSeed(seedDirectory)

    await expect(installManagedSeed({ seedDirectory, instanceDirectory })).resolves.toEqual({
      kind: 'installed',
      releaseId: 'ttss-test',
    })

    await writeFile(join(instanceDirectory, 'mods/example.jar'), 'automodpack-updated')
    await writeFile(join(instanceDirectory, 'resourcepacks/player.zip'), 'player-resource-pack')

    await expect(installManagedSeed({ seedDirectory, instanceDirectory })).resolves.toEqual({
      kind: 'already-managed',
      releaseId: 'ttss-test',
    })
    await expect(readFile(join(instanceDirectory, 'mods/example.jar'), 'utf8')).resolves.toBe('automodpack-updated')
    await expect(readFile(join(instanceDirectory, 'resourcepacks/player.zip'), 'utf8')).resolves.toBe('player-resource-pack')
  })

  it('rejects a manifest whose signature was changed', async () => {
    const root = await mkdtemp(join(tmpdir(), 'xmcl-managed-seed-'))
    roots.push(root)
    const seedDirectory = join(root, 'seed')
    await createSeed(seedDirectory)
    await writeFile(join(seedDirectory, 'ttss-client-seed.manifest.sig'), 'tampered')

    await expect(installManagedSeed({
      seedDirectory,
      instanceDirectory: join(root, 'game', 'instances', '清汤闲水服务器'),
    })).rejects.toMatchObject({ name: 'ManagedSeedSignatureError' })
  })
})
