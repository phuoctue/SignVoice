"""Compare verified Colab checkpoints under the unchanged app stream runtime.

Audit IDs are excluded before accessing their source/feature files. New encoder,
prototypes and normalizers travel together. No deployment or policy search.
"""
import argparse
import ast
import copy
import csv
import json
from pathlib import Path
import time
import numpy as np
from .analyze_word_failures import new_session
from .diagnostic_replay import ATOL,RTOL,identity,plain,replay
from .ensemble import ProbabilityEnsemble
from .evaluate_fixed_components import InferenceMemo,digest,file_hash,metrics,paired,write_json

BRANCHES=('app','app_tcn','reference42_tcn','reference137_tcn','latest137_tcn',
          'latest137_export_score','latest137_pair_fixed')


def verify_original_metadata(rows,contract):
    expected={r['video_id']:r for r in contract['cohort']}
    ids=[r['item']['video_id'] for r in rows]
    if len(ids)!=len(expected) or len(set(ids))!=len(ids) or set(ids)!=set(expected):raise ValueError('Original journal cohort corrupt')
    for row in rows:
        if row['item']!=expected[row['item']['video_id']] or row['contract_sha256']!=digest(contract):
            raise ValueError('Original journal contract corrupt')
        if not row['results']['null_control_passed']:raise ValueError('Original reference control failed')


def select_cohort(rows,training_identity):
    parts={k:set(training_identity[k]) for k in ('train_ids','epoch_val_ids','calibration_ids','audit_ids')}
    for a,x in parts.items():
        if len(x)!=len(training_identity[a]):raise ValueError('Duplicate split IDs')
        if any(x&y for b,y in parts.items() if a!=b):raise ValueError('Overlapping new split roles')
    selected=[];excluded=[]
    for row in rows:
        if row['item']['role']!='calibration_development':continue
        item=row['item'];key=item['video_id']
        if key in parts['train_ids']:raise ValueError('New model trained on evaluation video: '+key)
        if key in parts['audit_ids']:
            excluded.append(dict(video_id=key,reason='reserved_new_checkpoint_audit'));continue
        if key in parts['calibration_ids']:role='checkpoint_calibration_development'
        elif key in parts['epoch_val_ids']:role='checkpoint_epoch_development'
        else:raise ValueError('Missing frozen role: '+key)
        selected.append(dict(original=row,item={**item,'original_role':item['role'],'role':role}))
    return selected,excluded


def verify_assets(assets,engine,original_contract,selected):
    inventory=json.loads((assets/'inventory.json').read_text(encoding='utf-8'))
    for name,wanted in inventory['shared_expected'].items():
        if Path(name).name!=name or file_hash(assets/name)!=wanted:raise ValueError('Invalid shared asset: '+name)
    training=json.loads((assets/'training_identity.json').read_text(encoding='utf-8'))
    configs={}
    for spec in inventory['models']:
        for key,hash_key in [('model','model_sha256'),('config','config_sha256')]:
            if Path(spec[key]).name!=spec[key] or file_hash(assets/spec[key])!=spec[hash_key]:raise ValueError('Changed checkpoint asset')
        config=json.loads((assets/spec['config']).read_text(encoding='utf-8'));configs[spec['key']]=config
        base=engine.base.word_head
        if (config['labels']!=base.names or config['steps']!=48 or config['inputs']!={'hand_shape':126,'motion_context':19}
            or config.get('pair_gate_mode','measured')!='measured'
            or config['dynamic_labels']!=base.config['dynamic_labels']
            or any(config.get('requires_pair',{}).get(w,False)!=base.config.get('requires_pair',{}).get(w,False) for w in base.names)):
            raise ValueError('Checkpoint feature/label/gate contract differs')
        if any(r['item']['video_id'] in config['train_video_ids'] for r in selected):raise ValueError('TRAIN overlap')
        if any(r['item']['video_id'] in config['audit_val_video_ids'] for r in selected):raise ValueError('AUDIT access refused')
        if not set(config['train_video_ids'])<=set(training['train_ids']):raise ValueError('Unrecorded checkpoint TRAIN IDs')
        if not set(config['audit_val_video_ids'])<=set(training['audit_ids']):raise ValueError('Inconsistent audit IDs')
        if set(config['calibration']['video_ids'])!=set(training['calibration_ids']):raise ValueError('Inconsistent calibration IDs')
    # Recheck feature function ASTs rather than trusting inventory's booleans.
    trees=[ast.parse(Path(__file__).with_name('model_runtime.py').read_text(encoding='utf-8')),
           ast.parse((assets/'frozen_colab_runtime.py').read_text(encoding='utf-8'))]
    nodes=[{n.name:n for n in t.body if isinstance(n,(ast.FunctionDef,ast.ClassDef))} for t in trees]
    for name in inventory['compatibility_ast_equal']:
        if ast.dump(nodes[0][name],include_attributes=False)!=ast.dump(nodes[1][name],include_attributes=False):
            raise ValueError('Feature runtime changed: '+name)
    with (assets/'source_split_manifest.csv').open(encoding='utf-8-sig') as f:source=list(csv.DictReader(f))
    by_id={r['video_id']:r for r in source}
    train=[by_id[key] for key in training['train_ids']]
    for field in ('content_hash','source_sha256'):
        known={r[field] for r in train if r[field]}
        if any(by_id[r['item']['video_id']][field] in known for r in selected):raise ValueError('TRAIN content duplicate')
    for row in selected:
        if by_id[row['item']['video_id']]['content_hash']!=row['item']['content_sha1']:raise ValueError('Source identity changed')
    if training['feature_pipeline']!=engine.base.config['feature_pipeline']:raise ValueError('Feature pipeline mismatch')
    return inventory,configs


def load_neural(engine,assets,inventory):
    import tensorflow as tf
    models={};functions={};checks={}
    rng=np.random.default_rng(20261022)
    for spec in inventory['models']:
        model=tf.keras.models.load_model(assets/spec['model'],compile=False)
        if model.input_shape!=[(None,48,126),(None,48,19)] or model.output_shape!=(None,182):raise ValueError('TCN tensor schema differs')
        def make_graph(m):
            @tf.function(input_signature=[tf.TensorSpec((None,48,126),tf.float32),tf.TensorSpec((None,48,19),tf.float32)])
            def graph(shape,motion):return m([shape,motion],training=False)
            def infer(inputs):return graph(tf.convert_to_tensor(inputs[0]),tf.convert_to_tensor(inputs[1])).numpy()
            return infer
        infer=make_graph(model)
        for n in (1,3):
            x=rng.normal(0,.1,(n,48,126)).astype(np.float32);w=rng.normal(0,.1,(n,48,19)).astype(np.float32)
            a=model([x,w],training=False).numpy();b=infer([x,w])
            if not np.isfinite(b).all() or not np.allclose(b.sum(axis=1),1,atol=1e-3) or not np.allclose(a,b,atol=ATOL,rtol=RTOL):
                raise ValueError('Eager/graph control failed')
        models[spec['key']]=model;functions[spec['key']]=infer;checks[spec['key']]=dict(eager_graph_batches=[1,3],passed=True)
    encoder=tf.keras.models.load_model(assets/'embedding_model_v2.keras',custom_objects=engine.runtime.keras_custom_objects(tf),compile=False)
    if encoder.input_shape!=(None,40,126):raise ValueError('Encoder input shape differs')
    @tf.function(input_signature=[tf.TensorSpec((None,40,126),tf.float32)])
    def embed_graph(x):return encoder(x,training=False)
    def embed(x):return embed_graph(tf.convert_to_tensor(x)).numpy()
    for n in (1,3):
        x=rng.normal(0,.1,(n,40,126)).astype(np.float32)
        if not np.allclose(embed(x),encoder(x,training=False).numpy(),atol=ATOL,rtol=RTOL):raise ValueError('Encoder graph control failed')
    prototypes=json.loads((assets/'prototypes_v2.json').read_text(encoding='utf-8'))
    if set(prototypes)!=set(engine.base.labels):raise ValueError('Prototype labels differ')
    centers=engine.runtime.unit(np.asarray([prototypes[w] for w in engine.base.labels],np.float32))
    if encoder.output_shape!=(None,centers.shape[1]):raise ValueError('Encoder/prototype dimensions differ')
    mean=np.load(assets/'train_mean.npy',allow_pickle=False);std=np.load(assets/'train_std.npy',allow_pickle=False)
    if not np.array_equal(mean,engine.base.word_head.mean) or not np.array_equal(std,engine.base.word_head.std):
        raise ValueError('Normalizer portability control failed')
    checks['encoder']=dict(eager_graph_batches=[1,3],passed=True)
    return dict(functions=functions,embed=embed,centers=centers,mean=mean,std=std,models=models,encoder=encoder,checks=checks)


def make_sessions(engine,neural,configs):
    old_infer=InferenceMemo(engine.base.word_head.infer);old_embed=InferenceMemo(engine.base.word_head.embed)
    new_infer={k:InferenceMemo(v) for k,v in neural['functions'].items()};new_embed=InferenceMemo(neural['embed'])
    sessions={}
    for name in BRANCHES:
        s=new_session(engine,old_infer,old_embed);base=engine.base.word_head
        if name=='app':sessions[name]=s;continue
        config=copy.deepcopy(base.config);config['policy']={**base.policy,'embed_weight':0.}
        infer=old_infer;embed=None;centers=None;fusion=None
        if name!='app_tcn':
            key=name.split('_')[0];infer=new_infer[key]
            if name=='latest137_export_score':config=copy.deepcopy(configs[key])
            if name=='latest137_pair_fixed':
                config['policy']={**base.policy,'embed_weight':.5}
                embed=new_embed;centers=neural['centers']
                fusion=ProbabilityEnsemble(dict(tcn_weight=.5,tcn_temperature=1.,embedding_temperature=.06))
        s.recognizer.word_head=engine.runtime.TemporalWordHead(list(base.labels),config,infer,
            embed=embed,centers=centers,mean=neural['mean'],std=neural['std'],probability_fusion=fusion)
        s.reset();sessions[name]=s
    # Reference repeated last to verify that shared memo/model state is inert.
    sessions['app_repeat']=new_session(engine,old_infer,old_embed)
    return sessions


def evaluate(engine,neural,configs,arrays,saved):
    sessions=make_sessions(engine,neural,configs);results={};reference=[]
    for name,session in sessions.items():
        for i,(p,w,t,c) in enumerate(zip(*arrays)):
            session.update(p,w,float(t),context=c)
            score=session.decision.smoothed
            if name=='app':reference.append((None if score is None else score.copy(),plain(session.output)))
            elif name=='app_repeat':
                wanted,output=reference[i]
                if score is None or wanted is None:
                    if score is not None or wanted is not None:raise RuntimeError('Reference null mismatch')
                elif not np.allclose(score,wanted,atol=ATOL,rtol=RTOL):raise RuntimeError('Reference score changed')
                if plain(session.output)!=output:raise RuntimeError('Reference output changed')
        results[name]=dict(pred=session.events[-1]['label'] if session.events else None,events=plain(session.events))
    if results['app']!=saved:raise RuntimeError('Reference event history differs')
    if results.pop('app_repeat')!=results['app']:raise RuntimeError('Repeated reference changed')
    return dict(**results,null_control_passed=True,frames_controlled=len(arrays[2]))


def summary(rows):
    def group(items):
        values={name:metrics(items,name) for name in BRANCHES};comparisons={}
        # paired() uses the conventional name reference; keep app as the frozen reference.
        paired_rows=[{**r,'results':{**r['results'],'reference':r['results']['app']}} for r in items]
        for name in BRANCHES[1:]:comparisons[name]=paired(paired_rows,name)
        return dict(metrics=values,paired=comparisons)
    cal=[r for r in rows if r['item']['role']=='checkpoint_calibration_development']
    epoch=[r for r in rows if r['item']['role']=='checkpoint_epoch_development']
    return dict(calibration=group(cal),epoch_development=group(epoch),
        calibration_excluding_unverified_chao=group([r for r in cal if not r['item']['unverified_chao_khangcn']]),
        development_only=True,deployment_eligible=False,audit_arrays_loaded=False,real_background_measured=False,
        interpretation='Checkpoint portability in the app runtime at fixed operating points, not reproduction of published Colab metrics',
        fixed_new_fusion_is_recalibrated=False)


def webcam_probe(engine,neural,configs,capture):
    if identity(engine,'words')!=capture['worker_identity']:raise ValueError('Capture identity mismatch')
    if capture.get('truncated') or any(m.get('worker_diagnostic',{}).get('truncated') for m in capture['messages']):raise ValueError('Truncated capture')
    rows=[r for m in capture['messages'] for r in m.get('worker_diagnostic',{}).get('records',[])]
    sessions=make_sessions(engine,neural,configs);out={}
    for name,s in sessions.items():
        if name in ('app','app_repeat'):
            control=replay(s,rows)
            if not control['passed']:raise ValueError('Webcam control failed')
            out[name]=dict(events=plain(s.events),control=control);continue
        generation=None
        for row in rows:
            if row['generation']!=generation:s.recognizer.set_mode(row['mode']);s.reset();generation=row['generation']
            for x in row['inputs']:
                s.update(np.asarray(x['pose'],np.float32),np.asarray(x['wrist'],np.float32),x['time'],
                    allow_prediction=x['allow_prediction'],context=np.asarray(x['context'],np.float32))
        out[name]=dict(events=plain(s.events))
    return dict(scope='previously viewed webcam development probe; not independent accuracy',branches=out)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--assets',type=Path,required=True)
    p.add_argument('--model-dir',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--webcam',type=Path,required=True);p.add_argument('--smoke',action='store_true')
    a=p.parse_args()
    old=json.loads((a.input/'contract.json').read_text(encoding='utf-8'))
    raw=[json.loads(line) for line in (a.input/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    verify_original_metadata(raw,old)
    training=json.loads((a.assets/'training_identity.json').read_text(encoding='utf-8'))
    selected,excluded=select_cohort(raw,training)
    if len(selected)!=204 or len(excluded)!=93:raise ValueError('Unexpected cohort partition')
    if a.smoke:
        # One correct/none/wrong per role, when present, strictly engineering only.
        picked=[]
        for role in ('checkpoint_calibration_development','checkpoint_epoch_development'):
            subset=[r for r in selected if r['item']['role']==role]
            for state in ('correct','none','wrong'):
                options=[r for r in subset if ('none' if r['original']['results']['reference']['pred'] is None else
                    'correct' if r['original']['results']['reference']['pred']==r['item']['label'] else 'wrong')==state]
                picked+=options[:1]
        selected=picked
    from .engine import Engine
    engine=Engine(a.model_dir);before=identity(engine,'words')
    if before!=old['model_identity']:raise ValueError('App baseline changed')
    inventory,configs=verify_assets(a.assets,engine,old,selected)
    neural=load_neural(engine,a.assets,inventory)
    contract=dict(version=1,smoke=a.smoke,code_sha256=file_hash(__file__),model_identity=before,
        dependencies={n:file_hash(Path(__file__).with_name(n)) for n in ['analyze_word_failures.py','diagnostic_replay.py','evaluate_fixed_components.py','ensemble.py']},
        old_contract_sha256=digest(old),assets_inventory_sha256=file_hash(a.assets/'inventory.json'),
        inventory=inventory,cohort=[r['item'] for r in selected],excluded=excluded,branches=list(BRANCHES),
        graph_controls=neural['checks'],native_colab_stream_settings_reproduced=False,
        stream_settings='Unchanged app: prediction interval .25, gap .60, same causal buffer/windows',
        primary_role='checkpoint_calibration_development',secondary_role='checkpoint_epoch_development',
        fusion_point='Latest matched encoder/prototypes at fixed .5/1.0/.06, .6/.2/.3; transferred point, NOT recalibrated',
        checkpoint_comparison='TCN weights only at common app .6/.2/.3, plus latest export score .8 under the same app stream',
        automatic_model_selection=False,real_background_measured=False,audit_access=False,
        webcam_sha256=file_hash(a.webcam))
    a.output.mkdir(parents=True,exist_ok=True);path=a.output/'contract.json'
    if path.exists() and json.loads(path.read_text(encoding='utf-8'))!=contract:raise ValueError('Changed contract; choose another folder')
    write_json(path,contract);journal=a.output/'results.jsonl';done={}
    if journal.exists():
        for line in journal.read_text(encoding='utf-8').splitlines():
            row=json.loads(line);key=row['item']['video_id']
            if key in done or row['contract_sha256']!=digest(contract):raise ValueError('Invalid journal')
            done[key]=row
    expected={r['item']['video_id']:r for r in selected}
    if any(k not in expected or r['item']!=expected[k]['item'] for k,r in done.items()):raise ValueError('Changed resumed cohort')
    start=time.perf_counter()
    for row in selected:
        item=row['item'];key=item['video_id']
        if key in done:continue
        # Only the permitted 204 IDs reach this point; no audit data is opened.
        feature=a.input/'features'/(key+'.npz');source=a.input/'sources'/(key+'.mp4')
        metadata=row['original']['features']
        if file_hash(feature)!=metadata['feature_sha256'] or file_hash(source)!=metadata['source_sha256']:raise ValueError('Changed source/feature')
        with np.load(feature,allow_pickle=False) as z:arrays=tuple(z[k].copy() for k in ('pose','wrist','times','context'))
        result=evaluate(engine,neural,configs,arrays,{k:row['original']['results']['reference'][k] for k in ('pred','events')})
        value=dict(contract_sha256=digest(contract),item=item,features=metadata,results=result)
        with journal.open('a',encoding='utf-8') as f:f.write(json.dumps(plain(value),ensure_ascii=False,allow_nan=False)+'\n');f.flush()
        done[key]=value
        write_json(a.output/'status.json',dict(processed=len(done),expected=len(selected),complete=len(done)==len(selected)))
        if len(done)%20==0 or len(done)==len(selected):print(f'{len(done)}/{len(selected)}',flush=True)
    report=summary([done[r['item']['video_id']] for r in selected])
    report['webcam']=webcam_probe(engine,neural,configs,json.loads(a.webcam.read_text(encoding='utf-8')))
    report.update(complete=len(done)==len(selected),smoke_only=a.smoke,null_controls_passed=len(done),elapsed_seconds=time.perf_counter()-start)
    if identity(engine,'words')!=before:raise RuntimeError('App identity mutated')
    verify_assets(a.assets,engine,old,selected)
    write_json(a.output/'comparison.json',report)
    print(json.dumps(dict(complete=True,clips=len(done),calibration={k:{n:v[n] for n in ['correct','wrong','none','accepted_precision','wrong_events']} for k,v in report['calibration']['metrics'].items()},webcam={k:v['events'] for k,v in report['webcam']['branches'].items()}),ensure_ascii=True,indent=2))


if __name__=='__main__':main()
