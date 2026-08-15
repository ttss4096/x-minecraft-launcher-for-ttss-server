import { createHash, generateKeyPairSync, sign } from 'crypto'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'fs/promises'
import { tmpdir } from 'os'
import { join } from 'path'
import { afterEach, describe, expect, it } from 'vitest'
import { ZipFile } from 'yazl'
import { prepareManagedLauncher } from './managedBootstrap'

const roots: string[] = []

afterEach(async () => {
  await Promise.all(roots.splice(0).map(root => rm(root, { recursive: true, force: true })))
})

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
  const payloadFile = Buffer.from('managed payload')
  const zip = new ZipFile()
  zip.addBuffer(payloadFile, 'mods/managed.jar')
  const payload = await finishZip(zip)
  const manifest = Buffer.from(JSON.stringify({
    schemaVersion: 1,
    packId: 'ttss-ciap-1.21.1',
    releaseId: 'test-release',
    contentDigest: sha256(payloadFile),
    payload: { file: 'ttss-client-seed.zip', sha256: sha256(payload) },
    versions: { minecraft: '1.21.1', neoforge: '21.1.236', automodpack: '4.0.6-ttss-managed.2' },
    mutableRoots: ['resourcepacks', 'shaderpacks'],
    files: [{ path: 'mods/managed.jar', size: payloadFile.byteLength, sha256: sha256(payloadFile), mutable: false }],
  }))
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 })
  await mkdir(seedDirectory, { recursive: true })
  await Promise.all([
    writeFile(join(seedDirectory, 'ttss-client-seed.zip'), payload),
    writeFile(join(seedDirectory, 'ttss-client-seed.manifest.json'), manifest),
    writeFile(join(seedDirectory, 'ttss-client-seed.manifest.sig'), sign('sha256', manifest, privateKey)),
    writeFile(join(seedDirectory, 'ttss-client-seed.public.pem'), publicKey.export({ type: 'spki', format: 'pem' })),
  ])
}

describe('prepareManagedLauncher', () => {
  it('installs the only managed instance and pins the launcher root', async () => {
    const root = await mkdtemp(join(tmpdir(), 'ttss-managed-bootstrap-'))
    roots.push(root)
    const seedDirectory = join(root, 'seed')
    const appDataPath = join(root, 'launcher')
    await createSeed(seedDirectory)

    const first = await prepareManagedLauncher({ appDataPath, seedDirectory })
    expect(first.seedResult.kind).toBe('installed')
    expect(await readFile(join(appDataPath, 'root'), 'utf8')).toBe(first.gameDataPath)
    expect(JSON.parse(await readFile(join(first.instanceDirectory, '.ttss-managed', 'seed-state.json'), 'utf8')).phase).toBe('MANAGED_BY_AUTOMODPACK')

    const second = await prepareManagedLauncher({ appDataPath, seedDirectory })
    expect(second.seedResult.kind).toBe('already-managed')
  })
})
