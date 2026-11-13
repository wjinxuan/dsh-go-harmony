export interface PermissionCopy {
  title: string;
  hint: string;
}

export interface PermissionConfirmation {
  title: string;
  body: string;
  action: string;
}

export function permissionCopy(value: string, hostName: string, hostDescription: string, local: boolean): PermissionCopy {
  switch (value) {
    case 'read-only': return { title: '仅可查看', hint: '只看文件，不做修改' };
    case 'workspace-write': return { title: '工作区内修改',
      hint: local ? '可改应用工作区内的文件' : '可改工作区内的文件，越界先问你' };
    case 'danger-full-access': return { title: '完全权限',
      hint: local ? '应用工作区内的修改可直接执行' : '不再确认，直接执行' };
    case 'auto': return { title: '自动审查', hint: '由模型逐次审查，拿不准再问你' };
    case 'custom': return { title: '自定义', hint: hostDescription };
    default: return { title: hostName.trim() || value, hint: hostDescription };
  }
}

export function permissionConfirmation(value: string, local: boolean): PermissionConfirmation | undefined {
  if (value === 'danger-full-access') {
    return { title: '开启完全权限？', action: '开启完全权限',
      body: local ? 'AI 修改应用工作区文件前不再问你。文件访问仍限定在应用工作区。' :
        'AI 执行命令、改动文件前不再问你。' };
  }
  if (value === 'auto') {
    return { title: '开启自动审查？', body: '每次操作由模型判断放不放行，可能误判。', action: '开启自动审查' };
  }
  return undefined;
}
