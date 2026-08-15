import { open, openEntryReadStream, walkEntriesGenerator } from '@xmcl/unzip'
import { createHash, verify } from 'crypto'
import { createWriteStream } from 'fs'
import { ensureDir, pathExists, readFile, readJson, rename, rm, writeFile } from 'fs-extra'
import { dirname, join, posix } from 'path'
import { pipeline } from 'stream/promises'
import { Transform } from 'stream'
import { z } from 'zod'

const digestSchema = z.string().regex(/^[0-9a-f]{64}$/)
const seedFileSchema = z.object({
  path: z.string().min(1),
  size: z.number().int().nonnegative(),
  sha256: digestSchema,
  mutable: z.boolean(),
})
const seedManifestSchema = z.object({
  schemaVersion: z.literal(1),
  packId: z.literal('ttss-ciap-1.21.1'),
  releaseId: z.string().min(1),
  contentDigest: digestSchema,
  payload: z.object({
    file: z.literal('ttss-client-seed.zip'),
    sha256: digestSchema,
  }),
  versions: z.object({
    minecraft: z.literal('1.21.1'),
    neoforge: z.literal('21.1.236'),
    automodpack: z.literal('4.0.6-ttss-managed.2'),
  }),
  mutableRoots: z.array(z.string()),
  files: z.array(seedFileSchema).min(1),
})
const seedStateSchema = z.object({
  schemaVersion: z.literal(1),
  phase: z.union([z.literal('SEED_VERIFIED'), z.literal('MANAGED_BY_AUTOMODPACK')]),
  packId: z.literal('ttss-ciap-1.21.1'),
  releaseId: z.string().min(1),
  contentDigest: digestSchema,
})

type InstallManagedSeedOptions = {
  readonly seedDirectory: string
  readonly instanceDirectory: string
}

type InstallManagedSeedResult =
  | { readonly kind: 'installed'; readonly releaseId: string }
  | { readonly kind: 'already-managed'; readonly releaseId: string }

export class ManagedSeedError extends Error {
  constructor(readonly code: string, message: string) {
    super(message)
    this.name = code
  }
}

function isSafeArchivePath(path: string): boolean {
  if (!path || path.startsWith('/') || path.includes('\\') || path.includes('\0')) return false
  const normalized = posix.normalize(path)
  return normalized !== '..' && !normalized.startsWith('../') && normalized === path
}

async function sha256File(path: string): Promise<string> {
  const hash = createHash('sha256')
  const stream = (await import('fs')).createReadStream(path)
  for await (const chunk of stream) hash.update(chunk)
  return hash.digest('hex')
}

async function writeState(instanceDirectory: string, state: z.infer<typeof seedStateSchema>): Promise<void> {
  const statePath = join(instanceDirectory, '.ttss-managed', 'seed-state.json')
  const temporaryPath = `${statePath}.part`
  await ensureDir(dirname(statePath))
  await writeFile(temporaryPath, JSON.stringify(seedStateSchema.parse(state), null, 2))
  await rename(temporaryPath, statePath)
}

export async function installManagedSeed(options: InstallManagedSeedOptions): Promise<InstallManagedSeedResult> {
  const manifestPath = join(options.seedDirectory, 'ttss-client-seed.manifest.json')
  const signaturePath = join(options.seedDirectory, 'ttss-client-seed.manifest.sig')
  const publicKeyPath = join(options.seedDirectory, 'ttss-client-seed.public.pem')
  const payloadPath = join(options.seedDirectory, 'ttss-client-seed.zip')
  const [manifestBytes, signature, publicKey] = await Promise.all([
    readFile(manifestPath),
    readFile(signaturePath),
    readFile(publicKeyPath, 'utf8'),
  ])

  if (!verify('sha256', manifestBytes, publicKey, signature)) {
    throw new ManagedSeedError('ManagedSeedSignatureError', 'The TTSS seed manifest signature is invalid')
  }
  const manifest = seedManifestSchema.parse(JSON.parse(manifestBytes.toString('utf8')))
  if (await sha256File(payloadPath) !== manifest.payload.sha256) {
    throw new ManagedSeedError('ManagedSeedPayloadError', 'The TTSS seed payload hash is invalid')
  }

  const statePath = join(options.instanceDirectory, '.ttss-managed', 'seed-state.json')
  const existingState = await readJson(statePath).then(seedStateSchema.parse).catch(() => undefined)
  if (existingState?.phase === 'MANAGED_BY_AUTOMODPACK') {
    return { kind: 'already-managed', releaseId: existingState.releaseId }
  }
  if (existingState?.phase === 'SEED_VERIFIED') {
    await writeState(options.instanceDirectory, { ...existingState, phase: 'MANAGED_BY_AUTOMODPACK' })
    return { kind: 'installed', releaseId: existingState.releaseId }
  }
  if (await pathExists(options.instanceDirectory)) {
    throw new ManagedSeedError('ManagedSeedExistingInstanceError', 'The managed instance exists without a valid seed state')
  }

  const expectedFiles = new Map<string, z.infer<typeof seedFileSchema>>()
  for (const file of manifest.files) {
    if (!isSafeArchivePath(file.path) || expectedFiles.has(file.path)) {
      throw new ManagedSeedError('ManagedSeedManifestPathError', `The TTSS seed manifest contains an unsafe or duplicate path: ${file.path}`)
    }
    expectedFiles.set(file.path, file)
  }

  const stagingDirectory = `${options.instanceDirectory}.seed-installing`
  await rm(stagingDirectory, { recursive: true, force: true })
  await ensureDir(stagingDirectory)
  const seen = new Set<string>()
  const archive = await open(payloadPath)
  try {
    for await (const entry of walkEntriesGenerator(archive)) {
      if (entry.fileName.endsWith('/')) continue
      if (!isSafeArchivePath(entry.fileName) || seen.has(entry.fileName)) {
        throw new ManagedSeedError('ManagedSeedArchivePathError', `The TTSS seed archive contains an unsafe or duplicate path: ${entry.fileName}`)
      }
      const expected = expectedFiles.get(entry.fileName)
      if (!expected) {
        throw new ManagedSeedError('ManagedSeedUnexpectedFileError', `The TTSS seed archive contains an unexpected file: ${entry.fileName}`)
      }
      const destination = join(stagingDirectory, ...entry.fileName.split('/'))
      await ensureDir(dirname(destination))
      const hash = createHash('sha256')
      let size = 0
      const observer = new Transform({
        transform(chunk: Buffer, _encoding, callback) {
          hash.update(chunk)
          size += chunk.byteLength
          callback(null, chunk)
        },
      })
      await pipeline(await openEntryReadStream(archive, entry), observer, createWriteStream(destination, { mode: 0o644 }))
      if (size !== expected.size || hash.digest('hex') !== expected.sha256) {
        throw new ManagedSeedError('ManagedSeedFileHashError', `The TTSS seed file is invalid: ${entry.fileName}`)
      }
      seen.add(entry.fileName)
    }
  } catch (error) {
    await rm(stagingDirectory, { recursive: true, force: true })
    throw error
  } finally {
    archive.close()
  }
  if (seen.size !== expectedFiles.size) {
    await rm(stagingDirectory, { recursive: true, force: true })
    throw new ManagedSeedError('ManagedSeedMissingFileError', 'The TTSS seed archive is incomplete')
  }

  await writeState(stagingDirectory, {
    schemaVersion: 1,
    phase: 'SEED_VERIFIED',
    packId: manifest.packId,
    releaseId: manifest.releaseId,
    contentDigest: manifest.contentDigest,
  })
  await ensureDir(dirname(options.instanceDirectory))
  await rename(stagingDirectory, options.instanceDirectory)
  await writeState(options.instanceDirectory, {
    schemaVersion: 1,
    phase: 'MANAGED_BY_AUTOMODPACK',
    packId: manifest.packId,
    releaseId: manifest.releaseId,
    contentDigest: manifest.contentDigest,
  })
  return { kind: 'installed', releaseId: manifest.releaseId }
}
