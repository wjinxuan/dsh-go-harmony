import { readFileSync } from 'node:fs';
import { defineTool } from '@deepseek-ai/dsh-tools';
import { phoneController } from './phone-service.mjs';
const catalog = JSON.parse(readFileSync(new URL('./phone-catalog.json', import.meta.url), 'utf8'));
export const name = 'harmony-phone-tools';
export const inject = ['tools', 'agents', 'attachments'];
export function renderPhoneOutput(_args, value) {
  const parsed = JSON.parse(value), attachment = parsed.imageAttachment;
  delete parsed.imageAttachment;
  return [{ type: 'text', text: JSON.stringify(parsed) }, ...(attachment ? [{ type: 'image', attachment }] : [])];
}
export function apply(ctx) {
  for (const tool of catalog) {
    const parameters = Object.fromEntries(Object.entries(tool.inputSchema.properties).map(([key, value]) => [key, { ...value, ...(tool.inputSchema.required.includes(key) ? { required: true } : {}) }]));
    ctx.tools.register(defineTool({ name: 'mcp__phone__' + tool.name, description: tool.description, parameters,
      output: { schema: { type: 'string' }, render: renderPhoneOutput },
      async execute(args, exec) {
        if (!exec.agent) throw new Error('Phone tools require an agent Session');
        const boundary = ctx.agents.turnBoundaryOf(exec.agent.session);
        if (boundary.openTurnStartSeq === null) throw new Error('Phone tools require an active turn');
        const taskId = `${exec.agent.id}:${boundary.openTurnStartSeq}`;
        const controller = phoneController(), result = await controller.request(tool.name, args, exec.agent.id, exec.signal, taskId);
        if (tool.name === 'screen' && result.image) {
          const image = result.image; delete result.image;
          try {
            exec.signal?.throwIfAborted();
            if (args.image !== true) throw new Error('No screenshot was requested');
            if (!['image/png', 'image/jpeg'].includes(image.mediaType) || typeof image.base64 !== 'string' || image.base64.length > 2000000) throw new Error('Invalid screenshot');
            result.imageAttachment = await ctx.attachments.saveImage({ data: Buffer.from(image.base64, 'base64'), mediaType: image.mediaType });
            exec.signal?.throwIfAborted();
            image.width = result.imageAttachment.width; image.height = result.imageAttachment.height;
            controller.observeImage(exec.agent.id, taskId, result.id, image);
            result.imageSize = { width: image.width, height: image.height }; result.observation = result.id;
          } catch (error) { if (exec.signal?.aborted) throw error; delete result.imageAttachment; delete result.observation; result.imageError = String(error.message).slice(0, 300); }
        }
        return JSON.stringify(result);
      }
    }));
  }
}
