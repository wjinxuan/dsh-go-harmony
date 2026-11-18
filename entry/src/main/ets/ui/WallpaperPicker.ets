import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { image } from '@kit.ImageKit'
import { WallpaperPreferences } from './AdvancedPreferencesData'
export async function pickWallpaper(context: common.UIAbilityContext, previous: WallpaperPreferences): Promise<WallpaperPreferences | undefined> {
  const options=new photoAccessHelper.PhotoSelectOptions()
  options.MIMEType=photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE; options.maxSelectNumber=1
  const uri=(await new photoAccessHelper.PhotoViewPicker().select(options)).photoUris[0]
  if (!uri) return undefined
  const file=await fileIo.open(uri,fileIo.OpenMode.READ_ONLY)
  const path=`${context.filesDir}/dsh-wallpaper-${util.generateRandomUUID()}.png`
  let saved=false
  try {
    const stat=await fileIo.stat(file.fd)
    if(stat.size<=0||stat.size>15*1024*1024)throw new Error('壁纸图片不能超过 15 MiB。')
    const source=image.createImageSource(file.fd)
    try {
      const info=await source.getImageInfo(),size=info.size
      if(size.width<=0||size.height<=0||size.width*size.height>100000000)throw new Error('图片尺寸过大或无效。')
      const scale=Math.min(1,4096/Math.max(size.width,size.height))
      const pixels=await source.createPixelMap({desiredSize:{width:Math.max(1,Math.round(size.width*scale)),height:Math.max(1,Math.round(size.height*scale))}})
      try {
        const packer=image.createImagePacker()
        try { const bytes=await packer.packing(pixels,{format:'image/png',quality:100});const target=await fileIo.open(path,fileIo.OpenMode.CREATE|fileIo.OpenMode.WRITE_ONLY)
          try { await fileIo.write(target.fd,bytes) } finally { await fileIo.close(target) }
        } finally { await packer.release() }
        const normalized=await pixels.getImageInfo(); saved=true
        return {path:path,on:true,width:normalized.size.width,height:normalized.size.height,zoom:1,alignX:0,alignY:0,blur:previous.blur,lighten:previous.lighten,dim:previous.dim}
      } finally { await pixels.release() }
    } finally { await source.release() }
  } finally { await fileIo.close(file); if(!saved) await fileIo.unlink(path).catch(()=>{}) }
}
export async function removeWallpaperCopy(context: common.Context, path: string): Promise<void> {
  if(new RegExp('^'+context.filesDir.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'/dsh-wallpaper-[a-zA-Z0-9-]+\\.png$').test(path)) await fileIo.unlink(path).catch(()=>{})
}
