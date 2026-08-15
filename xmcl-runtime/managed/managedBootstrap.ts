import { ensureDir, rename, writeFile } from 'fs-extra'
import { join } from 'path'
import { TTSS_MANAGED_INSTANCE_NAME } from './managedPolicy'
import { installManagedSeed } from './managedSeed'

export type PrepareManagedLauncherOptions = {
  readonly appDataPath: string
  readonly seedDirectory: string
  readonly gameDataPath?: string
}

export async function prepareManagedLauncher(options: PrepareManagedLauncherOptions): Promise<{
  readonly gameDataPath: string
  readonly instanceDirectory: string
  readonly seedResult: Awaited<ReturnType<typeof installManagedSeed>>
}> {
  const gameDataPath = options.gameDataPath ?? join(options.appDataPath, 'managed-game')
  const instanceDirectory = join(gameDataPath, 'instances', TTSS_MANAGED_INSTANCE_NAME)
  await ensureDir(options.appDataPath)
  const seedResult = await installManagedSeed({
    seedDirectory: options.seedDirectory,
    instanceDirectory,
  })
  const rootPath = join(options.appDataPath, 'root')
  const temporaryRootPath = `${rootPath}.part`
  await writeFile(temporaryRootPath, gameDataPath, 'utf8')
  await rename(temporaryRootPath, rootPath)
  return { gameDataPath, instanceDirectory, seedResult }
}
