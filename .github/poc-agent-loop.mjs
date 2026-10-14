// A disposable proof of live UI interaction and screenshot; never mutate the actual Richman repo.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const scratch=mkdtempSync(join(tmpdir(),'godot-agent-loop-live-'));
writeFileSync(join(scratch,'project.godot'),'config_version=5\n[application]\nconfig/name="Temp Interactive PoC"\nrun/main_scene="res://main.tscn"\nconfig/features=PackedStringArray("4.7")\n[display]\nwindow/size/viewport_width=400\nwindow/size/viewport_height=300\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n');
writeFileSync(join(scratch,'main.gd'),'extends Control\nfunc _on_pressed() -> void:\n  $Label.text = "AFTER_CLICK"\n  print("REAL_BUTTON_ACTIVATED")\n');
writeFileSync(join(scratch,'main.tscn'),[
 '[gd_scene load_steps=2 format=3]',
 '[ext_resource type="Script" path="res://main.gd" id="1"]',
 '[node name="Main" type="Control"]',
 'layout_mode = 3',
 'anchors_preset = 15',
 'anchor_right = 1.0',
 'anchor_bottom = 1.0',
 'script = ExtResource("1")',
 '[node name="Play" type="Button" parent="."]',
 'offset_left = 20.0',
 'offset_top = 20.0',
 'offset_right = 180.0',
 'offset_bottom = 90.0',
 'text = "CLICK TO PLAY"',
 '[node name="Label" type="Label" parent="."]',
 'offset_left = 20.0',
 'offset_top = 120.0',
 'offset_right = 250.0',
 'offset_bottom = 160.0',
 'text = "BEFORE_CLICK"',
 '[connection signal="pressed" from="Play" to="." method="_on_pressed"]'
].join('\n')+'\n');
const child=spawn('pnpm',['dlx','@beremaran/godot-agent-loop@3.0.1'],{
 cwd:scratch,
 env:{
  ...process.env,
  GODOT_PATH:'/usr/local/bin/godot',
  GODOT_MCP_ALLOWED_DIRS:scratch,
  GODOT_MCP_PRIVILEGED_GROUPS:'',
  GODOT_MCP_ALLOW_PRIVILEGED_COMMANDS:'false',
  GODOT_MCP_ALLOW_UNRESTRICTED:'false',
  GODOT_MCP_RUNTIME_PORT:'12937',
 },
 stdio:['pipe','pipe','pipe']
});
child.stdout.setEncoding('utf8');
let buffer='',idx=0,errBytes=0;const waiting=new Map();
child.stdout.on('data',s=>{
 buffer+=s;
 while(buffer.includes('\n')){
  const end=buffer.indexOf('\n'),line=buffer.slice(0,end).trim();
  buffer=buffer.slice(end+1);
  if(!line)continue;
  let m;try{m=JSON.parse(line)}catch{console.log('NONJSON STDOUT '+line.slice(0,100));continue;}
  if(waiting.has(m.id)){
   const t=waiting.get(m.id);clearTimeout(t.timer);waiting.delete(m.id);
   if(m.error)t.reject(new Error('Protocol '+JSON.stringify(m.error).slice(0,1000)));
   else t.resolve(m.result);
  }
 }
});
child.stderr.on('data',b=>{if(errBytes<8000)process.stderr.write(String(b).slice(0,8000-errBytes));errBytes+=b.length;});
child.on('exit',(c,s)=>{for(const t of waiting.values()){clearTimeout(t.timer);t.reject(new Error('Agent loop exited '+c+' '+s))}waiting.clear()});
function rpc(method,params,ms=120000){
 return new Promise((resolve,reject)=>{
  const id=++idx;
  const timer=setTimeout(()=>{waiting.delete(id);reject(new Error(method+' timed out'))},ms);
  waiting.set(id,{resolve,reject,timer});
  child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');
 });
}
function notify(method){child.stdin.write(JSON.stringify({jsonrpc:'2.0',method,params:{}})+'\n')}
function summary(r){
 return JSON.stringify({isError:r?.isError,structuredContent:r?.structuredContent,
  content:r?.content?.map(x=>x.type==='image'?{type:'image',byteLength:x.data?.length}:x.type==='text'?{type:'text',text:x.text?.slice(0,1350)}:{type:x.type})}).slice(0,2700)
}
async function tool(name,args={}){
 let r=await rpc('tools/call',{name,arguments:args});
 console.log('TOOL '+name+' '+summary(r));
 if(r?.isError)throw new Error(name+' returned isError: '+summary(r));
 return r;
}
let verdict='FAIL';
try{
 console.log('Agent Loop 3.0.1, Godot 4.7.2, Xvfb, SCRATCH ONLY; no private assets');
 const hello=await rpc('initialize',{protocolVersion:'2024-11-05',capabilities:{},clientInfo:{name:'isolated-game-observer',version:'1.0'}},180000);
 console.log('Initialized: '+JSON.stringify(hello).slice(0,700));
 notify('notifications/initialized');
 const list=await rpc('tools/list',{}),names=list.tools.map(x=>x.name);
 console.log('Advertised tools: '+names.join(', '));
 for(const x of ['run_project','stop_project','game_scenario','game_get_ui','game_screenshot'])assert.ok(names.includes(x),x+' missing');
 await tool('run_project',{projectPath:scratch},180000);
 const before=await tool('game_get_ui',{});
 assert.match(JSON.stringify(before),/BEFORE_CLICK/,'missing initial label');
 const beforeFrame=await tool('game_screenshot',{retainArtifact:false});
 assert.equal(beforeFrame.structuredContent?.data?.width,400,'expected rendered viewport width');
 assert.equal(beforeFrame.structuredContent?.data?.height,300,'expected rendered viewport height');
 await tool('game_scenario',{
  projectPath:scratch,
  name:'click visible button and observe changed rendered UI',
  timeoutSeconds:20,
  steps:[
   {type:'input',tool:'game_click',arguments:{x:65,y:55},label:'click the visible button'},
   {type:'assert',condition:{condition:'log',text:'REAL_BUTTON_ACTIVATED',fresh:false,timeoutSeconds:10},label:'button handler actually activated'},
   {type:'observe',tool:'game_get_ui',arguments:{},label:'read visible UI after click'},
   {type:'screenshot',label:'capture changed frame'}
  ]
 });
 const after=await tool('game_get_ui',{});
 assert.match(JSON.stringify(after),/AFTER_CLICK/,'did not reach changed visible UI');
 const afterFrame=await tool('game_screenshot',{retainArtifact:false});
 assert.ok(beforeFrame.structuredContent?.data?.sha256,'missing pre-click pixel digest');
 assert.ok(afterFrame.structuredContent?.data?.sha256,'missing post-click pixel digest');
 assert.notEqual(beforeFrame.structuredContent.data.sha256,afterFrame.structuredContent.data.sha256,'clicked UI had no rendered pixel change');
 console.log('SCREENSHOT before='+beforeFrame.structuredContent.data.sha256+' after='+afterFrame.structuredContent.data.sha256);
 verdict='PASS';
 console.log('RESULT: PASS temp game live input/UI change/rendered screenshot (Xvfb/Linux). NOT RUN: Richman4 title-to-save, OS-native/macOS, actual player perception.');
}catch(err){console.error('RESULT: FAIL '+(err?.stack??err));process.exitCode=1}
finally{
 try{await Promise.race([tool('stop_project',{}),new Promise((_,reject)=>setTimeout(()=>reject(new Error('stop timed out')),5000))]);}catch(e){console.log('Stop warning '+e.message)}
 child.kill('SIGTERM');
 rmSync(scratch,{recursive:true,force:true});
 console.log('Scratch cleaned. Verdict '+verdict);
}

