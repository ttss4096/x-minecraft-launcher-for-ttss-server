import { posix } from 'path'

export const TTSS_MANAGED_INSTANCE_NAME = '清汤闲水服务器' as const

const editableInstanceFields = new Set([
  'instancePath',
  'java',
  'resolution',
  'minMemory',
  'maxMemory',
  'assignMemory',
  'vmOptions',
  'mcOptions',
  'env',
  'prependCommand',
  'preExecuteCommand',
  'showLog',
  'hideLauncher',
  'fastLaunch',
  'disableElybyAuthlib',
  'disableAuthlibInjector',
  'lastAccessDate',
  'lastPlayedDate',
  'playtime',
])

const allowedRoutes = new Set([
  '/',
  '/save',
  '/resourcepacks',
  '/shaderpacks',
  '/blueprints',
  '/base-setting',
  '/setting',
  '/me',
  '/multiplayer',
])

export class ManagedLauncherPolicyError extends Error {
  readonly name = 'ManagedLauncherPolicyError'

  constructor(readonly operation: string) {
    super(`The managed launcher policy rejected ${operation}`)
  }
}

export function isManagedRouteAllowed(route: string): boolean {
  const path = route.split(/[?#]/, 1)[0] || '/'
  return allowedRoutes.has(path)
}

export function isManagedInstanceMutationAllowed(relativePath: string): boolean {
  if (!relativePath || relativePath.includes('\\') || relativePath.startsWith('/')) return false
  const normalized = posix.normalize(relativePath)
  if (normalized === '..' || normalized.startsWith('../')) return false
  const root = normalized.split('/', 1)[0]
  return root === 'resourcepacks' || root === 'shaderpacks'
}

export function areManagedInstanceEditFieldsAllowed(fields: readonly string[]): boolean {
  return fields.every(field => editableInstanceFields.has(field))
}

interface ManagedRuntimeVersions {
  minecraft?: string
  forge?: string
  fabricLoader?: string
  quiltLoader?: string
  optifine?: string
  neoForged?: string
  labyMod?: string
}

export function isManagedResolvedVersionChangeAllowed(
  current: string | undefined,
  next: string | undefined,
  runtime: ManagedRuntimeVersions,
): boolean {
  return !current
    && next === 'neoforge-21.1.236'
    && runtime.minecraft === '1.21.1'
    && runtime.neoForged === '21.1.236'
    && !runtime.forge
    && !runtime.fabricLoader
    && !runtime.quiltLoader
    && !runtime.optifine
    && !runtime.labyMod
}

export function assertManagedLauncherOperationAllowed(operation: string): void {
  throw new ManagedLauncherPolicyError(operation)
}
