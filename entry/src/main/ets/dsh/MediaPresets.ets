import type { MediaPreset } from './MediaData'

// v1.0.15 fallback for media plugins whose catalogue predates presets.
export const MEDIA_PRESETS: MediaPreset[] = [
  { id: 'ark-image', label: '火山方舟 · 图片', provider: 'ark', profile: 'ark-image',
    baseUrl: 'https://ark.cn-beijing.volces.com', responseFormat: '', models: ['doubao-seedream-5-0-pro-260628'], kind: 'image', keyGroup: 'ark' },
  { id: 'ark-video', label: '火山方舟 · 视频', provider: 'ark', profile: 'ark-video',
    baseUrl: 'https://ark.cn-beijing.volces.com', responseFormat: '', models: ['doubao-seedance-2-5-260628'], kind: 'video', keyGroup: 'ark' },
  { id: 'aliyun-image', label: '阿里云百炼 · 图片', provider: 'aliyun', profile: 'ali-wan-image',
    baseUrl: 'https://dashscope.aliyuncs.com', responseFormat: '', models: ['wan2.7-image'], kind: 'image', keyGroup: 'aliyun' },
  { id: 'aliyun-video', label: '阿里云百炼 · 视频', provider: 'aliyun', profile: 'ali-video',
    baseUrl: 'https://dashscope.aliyuncs.com', responseFormat: '', models: ['wan2.7-t2v-2026-06-12', 'wan2.7-i2v-2026-04-25'], kind: 'video', keyGroup: 'aliyun' },
  { id: 'siliconflow-image', label: '硅基流动 · 图片', provider: 'siliconflow', profile: 'silicon-image',
    baseUrl: 'https://api.siliconflow.cn', responseFormat: '', models: ['Qwen/Qwen-Image', 'Qwen/Qwen-Image-Edit-2509'], kind: 'image', keyGroup: 'siliconflow' },
  { id: 'siliconflow-video', label: '硅基流动 · 视频', provider: 'siliconflow', profile: 'silicon-video',
    baseUrl: 'https://api.siliconflow.cn', responseFormat: '', models: ['Wan-AI/Wan2.2-T2V-A14B', 'Wan-AI/Wan2.2-I2V-A14B'], kind: 'video', keyGroup: 'siliconflow' },
  { id: 'openai-image', label: 'OpenAI · 图片', provider: 'openai', profile: 'openai-gpt-image',
    baseUrl: 'https://api.openai.com/v1', responseFormat: '', models: ['gpt-image-2', 'gpt-image-2.5-sunburst', 'gpt-image-2.5-flare'], kind: 'image', keyGroup: 'openai' },
  { id: 'gemini-image', label: 'Gemini · 图片', provider: 'gemini', profile: 'openai-compatible',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai', responseFormat: 'b64_json', models: ['gemini-2.5-flash-image'], kind: 'image', keyGroup: 'gemini' }
]
