"""Registered six-point full-stream fusion calibration. Offline development only."""
import argparse
import copy
import csv
import json
from pathlib import Path
import time
import numpy as np
from .analyze_word_failures import new_session
from .compare_colab_checkpoints import verify_original_metadata,select_cohort,verify_assets,load_neural
from .diagnostic_replay import identity,plain,replay,ATOL,RTOL
from .ensemble import ProbabilityEnsemble
from .evaluate_fixed_components import InferenceMemo,digest,file_hash,write_json,metrics,paired
from .review_colab_checkpoints import contrast

SPECS={
    'anchor':dict(tcn_weight=.5,tcn_temperature=1.,embedding_temperature=.06),
    'tcn25':dict(tcn_weight=.25,tcn_temperature=1.,embedding_temperature=.06),
    'tcn75':dict(tcn_weight=.75,tcn_temperature=1.,embedding_temperature=.06),
    'tcn_sharper':dict(tcn_weight=.5,tcn_temperature=.75,embedding_temperature=.06),
    'embedding_sharper':dict(tcn_weight=.5,tcn_temperature=1.,embedding_temperature=.04),
    'embedding_softer':dict(tcn_weight=.5,tcn_temperature=1.,embedding_temperature=.09),
}
CRITICAL=('chào','nghe','nhìn','rau','bàn tay','cứu')
CAL='checkpoint_calibration_development'
EPOCH='checkpoint_epoch_development'


def selection(rows):
    cal=[r for r in rows if r['item']['role']==CAL and not r['item']['unverified_chao_khangcn']]
    if not cal:raise ValueError('No calibration rows for selection')
    if any(set(r['results'])!={'app',*SPECS} for r in cal):raise ValueError('Missing or unexpected calibration branches')
    base=metrics(cal,'anchor');tests={};eligible=[]
    for name in SPECS:
        if name=='anchor':continue
        m=metrics(cal,name)
        checks=dict(macro_recall_increased=m['macro_recall']>base['macro_recall'],
            correct_not_decreased=m['correct']>=base['correct'],
            precision_sufficient=m['accepted_precision'] is not None and
                m['accepted_precision']>=max(.95,base['accepted_precision'] or 0),
            wrong_not_increased=m['wrong']<=base['wrong'],wrong_events_not_increased=m['wrong_events']<=base['wrong_events'],
            duplicates_not_increased=m['consecutive_duplicate_events']<=base['consecutive_duplicate_events'],
            represented_critical_not_lost=all(m['by_label'].get(w,{}).get('correct',0)>=base['by_label'].get(w,{}).get('correct',0) for w in CRITICAL))
        tests[name]=dict(checks=checks,eligible=all(checks.values()),metrics=m)
        if all(checks.values()):eligible.append(name)
    def order(name):
        m=tests[name]['metrics'];s=SPECS[name];anchor=SPECS['anchor']
        distance=sum(abs(np.log(s[k]/anchor[k])) for k in anchor)
        return (-m['macro_recall'],-m['accepted_precision'],m['wrong_events'],distance,name)
    chosen=min(eligible,key=order) if eligible else 'anchor'
    return dict(nominee=chosen,reason='development_only_nominee' if eligible else 'no_supported_development_improvement',
        videos=len(cal),labels=len(base['by_label']),candidate_checks=tests,
        missing_critical=[w for w in CRITICAL if w not in base['by_label']],
        selection_uses_epoch=False,selection_uses_webcam=False,deployment_eligible=False)


def sessions(engine,neural,names):
    old=engine.base.word_head
    old_infer=InferenceMemo(old.infer);old_embed=InferenceMemo(old.embed)
    infer=InferenceMemo(neural['functions']['latest137']);embed=InferenceMemo(neural['embed'])
    result={}
    for name in names:
        s=new_session(engine,old_infer,old_embed)
        if name!='app':
            config=copy.deepcopy(old.config);config['policy']={**old.policy,'embed_weight':1-SPECS[name]['tcn_weight']}
            s.recognizer.word_head=engine.runtime.TemporalWordHead(list(old.labels),config,infer,embed=embed,
                centers=neural['centers'],mean=neural['mean'],std=neural['std'],probability_fusion=ProbabilityEnsemble(SPECS[name]))
            s.reset()
        result[name]=s
    for name in ('app','anchor'):
        # Separate state, but the same pure memoized neural functions.
        s=new_session(engine,old_infer,old_embed)
        if name=='anchor':
            config=copy.deepcopy(old.config);config['policy']={**old.policy,'embed_weight':.5}
            s.recognizer.word_head=engine.runtime.TemporalWordHead(list(old.labels),config,infer,embed=embed,
                centers=neural['centers'],mean=neural['mean'],std=neural['std'],probability_fusion=ProbabilityEnsemble(SPECS[name]))
            s.reset()
        result[name+'_repeat']=s
    return result


def evaluate(engine,neural,names,arrays,saved):
    collection=sessions(engine,neural,names);trace={};out={}
    for name,s in collection.items():
        reference=name.removesuffix('_repeat');repeated=name.endswith('_repeat')
        if name in ('app','anchor'):trace[name]=[]
        for i,(p,w,t,c) in enumerate(zip(*arrays)):
            s.update(p,w,float(t),context=c)
            score=s.decision.smoothed
            if name in ('app','anchor'):trace[name].append((None if score is None else score.copy(),plain(s.output)))
            if repeated:
                wanted,output=trace[reference][i]
                equal=(score is None and wanted is None) or (score is not None and wanted is not None
                    and score.shape==wanted.shape and np.allclose(score,wanted,atol=ATOL,rtol=RTOL))
                if not equal or plain(s.output)!=output:raise RuntimeError('Repeated control differs: '+name)
        out[name]=dict(pred=s.events[-1]['label'] if s.events else None,events=plain(s.events))
    for name in ('app','anchor'):
        if out.pop(name+'_repeat')!=out[name]:raise RuntimeError('Repeat event control failed')
        key='app' if name=='app' else 'latest137_pair_fixed'
        if out[name]!=saved[key]:raise RuntimeError('Frozen checkpoint reference differs: '+name)
    return out


def summarize_group(rows,names):
    data={name:metrics(rows,name) for name in names}
    contrasts={}
    for base in ('app','anchor'):
        paired_rows=[{**r,'results':{**r['results'],'reference':r['results'][base]}} for r in rows]
        contrasts[base]={name:dict(events=contrast(rows,base,name),bootstrap=paired(paired_rows,name)) for name in names if name!=base}
    return dict(metrics=data,contrasts=contrasts,development_only=True)


def webcam_probe(engine,neural,capture,names):
    if identity(engine,'words')!=capture['worker_identity']:raise ValueError('Webcam identity differs')
    if capture.get('truncated') or any(m.get('worker_diagnostic',{}).get('truncated') for m in capture['messages']):raise ValueError('Truncated webcam')
    rows=[r for m in capture['messages'] for r in m.get('worker_diagnostic',{}).get('records',[])]
    result={}
    for name,s in sessions(engine,neural,names).items():
        if name.startswith('app'):
            control=replay(s,rows)
            if not control['passed']:raise RuntimeError('Webcam app control failed')
            result[name]=dict(control=control,events=plain(s.events));continue
        generation=None
        for r in rows:
            if r['generation']!=generation:s.recognizer.set_mode(r['mode']);s.reset();generation=r['generation']
            for x in r['inputs']:
                s.update(np.asarray(x['pose'],np.float32),np.asarray(x['wrist'],np.float32),x['time'],
                    context=np.asarray(x['context'],np.float32),allow_prediction=x['allow_prediction'])
        result[name]=dict(events=plain(s.events))
    if result.pop('anchor_repeat')!=result['anchor']:raise RuntimeError('Webcam anchor repeat differs')
    result.pop('app_repeat')
    return dict(branches=result,scope='exposed development probe after frozen calibration choice',accuracy_measured=False)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('original','checkpoints','assets','model-dir','webcam','output'):p.add_argument('--'+name,required=True,type=Path)
    p.add_argument('--smoke',action='store_true');p.add_argument('--smoke-proof',type=Path)
    a=p.parse_args();started=time.perf_counter()
    old=json.loads((a.original/'contract.json').read_bytes())
    raw=[json.loads(line) for line in (a.original/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    verify_original_metadata(raw,old)
    selected,excluded=select_cohort(raw,json.loads((a.assets/'training_identity.json').read_bytes()))
    if len(selected)!=204 or len(excluded)!=93:raise ValueError('Unexpected split partition')
    prior_contract=json.loads((a.checkpoints/'contract.json').read_bytes())
    prior=[json.loads(line) for line in (a.checkpoints/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    by_id={r['item']['video_id']:r for r in prior}
    if len(by_id)!=204 or len(prior)!=204:raise ValueError('Incomplete checkpoint controls')
    for row in selected:
        item=row['item'];previous=by_id[item['video_id']]
        if previous['contract_sha256']!=digest(prior_contract) or previous['item']!=item or not previous['results']['null_control_passed']:
            raise ValueError('Invalid saved checkpoint control')
    dependencies={n:file_hash(Path(__file__).with_name(n)) for n in (
        'compare_colab_checkpoints.py','analyze_word_failures.py','evaluate_fixed_components.py','ensemble.py',
        'diagnostic_replay.py','review_colab_checkpoints.py','review_anchored_windows.py')}
    base=dict(version=1,code_sha256=file_hash(__file__),dependencies=dependencies,specs=SPECS,
        protocol_sha256=file_hash(Path(__file__).parents[1]/'docs/FUSION_CALIBRATION_PROTOCOL_20261022.md'),
        original_contract_sha256=digest(old),checkpoint_contract_sha256=digest(prior_contract),
        checkpoint_results_sha256=file_hash(a.checkpoints/'results.jsonl'),
        assets_inventory_sha256=file_hash(a.assets/'inventory.json'),model_identity=old['model_identity'],
        all_permitted_items=[r['item'] for r in selected],excluded_audit=excluded,webcam_sha256=file_hash(a.webcam),
        score=.60,dynamic_score=.60,margin=.20,dynamic_margin=.20,dwell=.30,interval=.25,gap=.60,
        primary_selection='calibration excluding unverified chao KhangCN',
        epoch_selection=False,webcam_selection=False,audit_arrays_loaded=False,background_measured=False,
        deployment_eligible=False)
    experiment_sha=digest(base)
    if a.smoke:
        subset=[]
        for role in (CAL,EPOCH):
            for state in ('correct','none','wrong'):
                found=[r for r in selected if r['item']['role']==role and
                    ('none' if by_id[r['item']['video_id']]['results']['app']['pred'] is None else
                     'correct' if by_id[r['item']['video_id']]['results']['app']['pred']==r['item']['label'] else 'wrong')==state]
                subset+=found[:1]
        selected=subset
    else:
        if a.smoke_proof is None:raise ValueError('Smoke proof required before FULL')
        proof=json.loads(a.smoke_proof.read_bytes())
        if not proof.get('smoke_only') or not proof.get('complete') or proof.get('experiment_sha256')!=experiment_sha:
            raise ValueError('Smoke not complete or code/contract changed')
    from .engine import Engine
    engine=Engine(a.model_dir);before=identity(engine,'words')
    if before!=old['model_identity']:raise ValueError('App baseline changed')
    inventory,configs=verify_assets(a.assets,engine,old,selected)
    neural=load_neural(engine,a.assets,{**inventory,'models':[s for s in inventory['models'] if s['key']=='latest137']})
    contract=dict(experiment=base,experiment_sha256=experiment_sha,smoke=a.smoke,
        cohort=[r['item'] for r in selected],neural_controls=neural['checks'])
    a.output.mkdir(parents=True,exist_ok=True);path=a.output/'contract.json'
    if path.exists() and json.loads(path.read_bytes())!=contract:raise ValueError('Contract changed: use another output directory')
    write_json(path,contract);journal=a.output/'results.jsonl';done={}
    expected={r['item']['video_id']:r for r in selected}
    if journal.exists():
        for line in journal.read_text(encoding='utf-8').splitlines():
            row=json.loads(line);key=row['item']['video_id']
            if key in done or key not in expected or row['contract_sha256']!=digest(contract) or row['item']!=expected[key]['item']:
                raise ValueError('Changed resumed journal')
            done[key]=row
    choice=None
    for role in (CAL,EPOCH):
        if role==EPOCH:
            choice=selection(list(done.values()))
            write_json(a.output/'frozen-nominee.json',dict(experiment_sha256=experiment_sha,**choice))
        names=['app',*SPECS] if role==CAL else list(dict.fromkeys(['app','anchor',choice['nominee']]))
        for row in [r for r in selected if r['item']['role']==role]:
            item=row['item'];key=item['video_id']
            if key in done:
                if set(done[key]['results'])!=set(names):raise ValueError('Resumed branch set differs from frozen choice')
                continue
            # Only selected non-TRAIN, non-AUDIT IDs can reach feature/source I/O.
            feature=a.original/'features'/(key+'.npz');source=a.original/'sources'/(key+'.mp4');meta=row['original']['features']
            if file_hash(feature)!=meta['feature_sha256'] or file_hash(source)!=meta['source_sha256']:raise ValueError('Changed source/feature')
            with np.load(feature,allow_pickle=False) as z:arrays=tuple(z[k].copy() for k in ('pose','wrist','times','context'))
            controls={n:{k:by_id[key]['results'][n][k] for k in ('pred','events')} for n in ('app','latest137_pair_fixed')}
            result=evaluate(engine,neural,names,arrays,controls)
            value=dict(contract_sha256=digest(contract),item=item,features=meta,results=result,
                frames_controlled=len(arrays[2]),null_controls_passed=True)
            with journal.open('a',encoding='utf-8') as f:f.write(json.dumps(plain(value),ensure_ascii=False,allow_nan=False)+'\n');f.flush()
            done[key]=value
            write_json(a.output/'status.json',dict(processed=len(done),expected=len(selected),complete=len(done)==len(selected)))
            if len(done)%10==0 or len(done)==len(selected):print(f'{len(done)}/{len(selected)} {role}',flush=True)
    cal=[r for r in done.values() if r['item']['role']==CAL];epoch=[r for r in done.values() if r['item']['role']==EPOCH]
    small=[r for r in cal if not r['item']['unverified_chao_khangcn']]
    epoch_names=list(dict.fromkeys(['app','anchor',choice['nominee']]))
    report=dict(complete=len(done)==len(selected),smoke_only=a.smoke,experiment_sha256=experiment_sha,
        calibration=summarize_group(cal,['app',*SPECS]),calibration_excluding_unverified=summarize_group(small,['app',*SPECS]),
        selection=choice,epoch=summarize_group(epoch,epoch_names),
        real_background_measured=False,audit_arrays_loaded=False,deployment_eligible=False,
        null_controls_passed=len(done),elapsed_seconds=time.perf_counter()-started)
    if not a.smoke:report['webcam']=webcam_probe(engine,neural,json.loads(a.webcam.read_bytes()),epoch_names)
    if identity(engine,'words')!=before:raise RuntimeError('App baseline mutated')
    verify_assets(a.assets,engine,old,selected)
    write_json(a.output/'comparison.json',report)
    print(json.dumps(dict(complete=report['complete'],clips=len(done),nominee=choice['nominee'],reason=choice['reason'],
        calibration={name:{k:v[k] for k in ('correct','wrong','none','accepted_precision','wrong_events','macro_recall')}
            for name,v in report['calibration_excluding_unverified']['metrics'].items()}),ensure_ascii=True,indent=2))


if __name__=='__main__':main()
