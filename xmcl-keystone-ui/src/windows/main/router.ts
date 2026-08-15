import BaseSetting from '@/views/BaseSetting.vue'
import BaseSettingActions from '@/views/BaseSettingActions.vue'
import BaseSettingExtension from '@/views/BaseSettingExtension.vue'
import Home from '@/views/Home.vue'
import HomeActions from '@/views/HomeActions.vue'
import HomeExtension from '@/views/HomeExtension.vue'
import HomeLayout from '@/views/HomeLayout.vue'
import Me from '@/views/Me.vue'
import Blueprint from '@/views/Blueprint.vue'
import BlueprintActions from '@/views/BlueprintActions.vue'
import BlueprintExtension from '@/views/BlueprintExtension.vue'
import Multiplayer from '@/views/Multiplayer.vue'
import ResourcePack from '@/views/ResourcePack.vue'
import ResourcePackActions from '@/views/ResourcePackActions.vue'
import ResourcePackExtension from '@/views/ResourcePackExtension.vue'
import Save from '@/views/Save.vue'
import SaveActions from '@/views/SaveActions.vue'
import SaveExtension from '@/views/SaveExtension.vue'
import Setting from '@/views/Setting.vue'
import ShaderPack from '@/views/ShaderPack.vue'
import ShaderPackActions from '@/views/ShaderPackActions.vue'
import ShaderPackExtension from '@/views/ShaderPackExtension.vue'
import { createRouter, createWebHashHistory } from 'vue-router'

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/',
      component: HomeLayout,
      children: [
        {
          path: '',
          components: {
            default: Home,
            extensions: HomeExtension,
            actions: HomeActions,
          },
        },
        {
          path: 'save',
          components: {
            default: Save,
            extensions: SaveExtension,
            actions: SaveActions,
          },
        },
        {
          path: 'resourcepacks',
          components: {
            default: ResourcePack,
            extensions: ResourcePackExtension,
            actions: ResourcePackActions,
          },
        },
        {
          path: 'shaderpacks',
          components: {
            default: ShaderPack,
            extensions: ShaderPackExtension,
            actions: ShaderPackActions,
          },
        },
        {
          path: 'blueprints',
          components: {
            default: Blueprint,
            extensions: BlueprintExtension,
            actions: BlueprintActions,
          },
        },
        {
          path: 'base-setting',
          components: {
            default: BaseSetting,
            extensions: BaseSettingExtension,
            actions: BaseSettingActions,
          },
        },
        {
          path: 'base-setting/modrinth-project',
          redirect: { path: '/base-setting', query: { target: 'modrinth-project' } },
        },
      ],
    },
    { path: '/mods/:pathMatch(.*)*', redirect: '/' },
    { path: '/store/:pathMatch(.*)*', redirect: '/' },
    {
      path: '/setting',
      component: Setting,
    },
    {
      path: '/me',
      component: Me,
    },
    {
      path: '/multiplayer',
      component: Multiplayer,
    },
  ],
})
