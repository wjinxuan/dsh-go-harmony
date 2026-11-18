import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../entry/src/main/ets/ui/ProfileShareData.ets',import.meta.url),'utf8').replace(/^import .*\n/m,'').replace(/export /g,'');
const array=v=>Array.isArray(v)?v:[],object=v=>v&&typeof v==='object'&&!Array.isArray(v)?v:{},string=v=>typeof v==='string'?v:'',strings=v=>array(v).filter(v=>typeof v==='string'),number=(v,f)=>typeof v==='number'?v:f;
const {ProfileShareController}=Function('array','object','string','strings','number',stripTypeScriptTypes(source)+';return {ProfileShareController}')(array,object,string,strings,number);
export {ProfileShareController};
