'use strict';
// Read-only harness: loads actual production module with isolated HTTP/database fakes.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const root=path.resolve(__dirname,'../../../../../../sozo-backend');
let repos=[],responses={},writes=[],deaths=[],requests=[];
const axios={get:async url=>{requests.push(url);const v=responses[url];if(v instanceof Error)throw v;if(v===undefined)throw Error('fixture missing '+url);return {data:v}}};
const CatalogSource={bulkWrite:async ops=>writes.push(...ops),updateMany:async (filter,update)=>{deaths.push({filter,update});return {modifiedCount:1}}};
const ExtensionRepo={find:()=>({sort:()=>({lean:async()=>repos})})};
function load(file){const module={exports:{}};vm.runInNewContext(fs.readFileSync(path.join(root,file),'utf8'),{module,exports:module.exports,require:n=>n==='axios'?axios:n.includes('ExtensionRepo')?ExtensionRepo:CatalogSource,Date,console},{filename:file});return module.exports}
const service=load('src/services/catalogIngest.service.js');
const report=[];
const source=(id,name)=>({id,name,sourceCodeLanguage:1,sourceCodeUrl:'https://fixture/'+id+'.js'});
function reset(){repos=[];responses={};writes=[];deaths=[];requests=[]}
(async()=>{
reset();repos=[{_id:'repo',kind:'mangayomi',name:'Fixture',url:'https://fixture/index.json',novelUrl:'https://fixture/novel_index.json'}];responses[repos[0].url]=[source('m','Manga')];responses[repos[0].novelUrl]=[source('n','Novel')];await service.ingestAll();const novel=writes.find(x=>x.updateOne.update.$set.itemType==='novel').updateOne.update.$set;assert.equal(novel.repoUrl,repos[0].url);report.push({case:'novel_install_targets_manga_index',actual:novel.repoUrl,expected:repos[0].novelUrl,confirmed:true});
reset();repos=[{_id:'repo',kind:'mangayomi',name:'Fixture',url:'https://fixture/index.json',novelUrl:'https://fixture/novel_index.json'}];responses[repos[0].url]=[source('m','Manga')];responses[repos[0].novelUrl]=Error('503');const partial=await service.ingestAll();assert.equal(deaths.length,1);report.push({case:'failed_novel_index_still_marks_unseen_repo_rows_dead',report:partial.repos,deathFilter:deaths[0].filter,confirmed:true});
reset();repos=[{_id:'repo',kind:'manga',name:'Fixture',url:'https://fixture/index.pb'}];responses['https://fixture/index.min.json']='<html>maintenance</html>';await service.ingestAll();assert.equal(writes.length,0);assert.equal(deaths.length,1);report.push({case:'malformed_200_index_marks_entire_catalog_repo_dead',requests,confirmed:true});
reset();responses['https://fixture/direct.json']=[{name:'Plugin',internalName:'plugin',url:'https://fixture/plugin.cs3',language:'en'}];const direct=await service.harvestRepo({kind:'cloudstream',url:'https://fixture/direct.json'});assert.equal(direct.length,0);report.push({case:'cloudstream_direct_plugin_array_ignored',count:direct.length,confirmed:true});
reset();responses['https://fixture/repo.json']={pluginLists:['https://fixture/list.json']};responses['https://fixture/list.json']=[{name:'Down',internalName:'down',status:0,language:'en'}];const down=await service.harvestRepo({kind:'cloudstream',url:'https://fixture/repo.json'});assert.equal(down.length,1);report.push({case:'cloudstream_status_down_listed',rows:down,confirmed:true});
reset();responses['https://fixture/index.json']=[{...source('old','Legacy JS'),sourceCodeLanguage:undefined}];const legacy=await service.harvestRepo({kind:'mangayomi',url:'https://fixture/index.json'});assert.equal(legacy[0].jsRuntime,false);report.push({case:'missing_language_flag_not_runnable_server_but_client_defaults_js',jsRuntime:legacy[0].jsRuntime,confirmed:true});
console.log(JSON.stringify({generatedAt:new Date().toISOString(),productionModule:path.join(root,'src/services/catalogIngest.service.js'),tests:report},null,2));
})().catch(e=>{console.error(e);process.exitCode=1});
