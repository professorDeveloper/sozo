'use strict';
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../../../../../../sozo-backend');
const axios=require(path.join(root,'node_modules/axios/dist/node/axios.cjs'));
const urls=[
'https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.min.json',
'https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.pb',
'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb',
'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/novel_index.json'
];
(async()=>{const evidence=await Promise.all(urls.map(async url=>{try{const r=await axios.get(url,{timeout:20000,responseType:'arraybuffer',validateStatus:()=>true,maxContentLength:5e6});const b=Buffer.from(r.data);let data;try{data=JSON.parse(b.toString())}catch{}return {url,status:r.status,bytes:b.length,magic:b.subarray(0,4).toString('hex'),rows:Array.isArray(data)?data.length:null,sample:Array.isArray(data)?data.slice(0,3).map(e=>({id:e.id,name:e.name,pkg:e.pkg,itemType:e.itemType,sourceCodeLanguage:e.sourceCodeLanguage,sourceCodeUrl:e.sourceCodeUrl,sources:e.sources?.slice(0,2)})):undefined};}catch(e){return{url,error:e.message}}}));console.log(JSON.stringify({fetchedAt:new Date().toISOString(),evidence},null,2))})()
