"""Verify a completed frozen journal and review TRAIN rau cut-vs-stream outputs."""
import argparse
import copy
import json
from pathlib import Path
import numpy as np
from .diagnostic_replay import identity, plain
from .evaluate_fixed_components import (VARIANTS, ComponentFusion, InferenceMemo, digest,
                                        file_hash, metrics, summarize, write_json)


def verify(root):
    contract = json.loads((root/'contract.json').read_text(encoding='utf-8'))
    report = json.loads((root/'comparison.json').read_text(encoding='utf-8'))
    if not report['complete']: raise ValueError('Incomplete run; no final reading')
    expected = {i['video_id']:i for i in contract['cohort']}
    rows = [json.loads(line) for line in (root/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    if len(rows) != len(expected) or len({r['item']['video_id'] for r in rows}) != len(rows):
        raise ValueError('Missing/duplicate journal rows')
    for row in rows:
        item = row['item']; key = item['video_id']
        if item != expected[key] or row['contract_sha256'] != digest(contract):
            raise ValueError('Cohort/contract mismatch')
        if not row['results']['null_control_passed']: raise ValueError('Reference null control failed')
        feature = root/'features'/(key+'.npz')
        source = root/'sources'/(key+'.mp4')
        if file_hash(feature) != row['features']['feature_sha256'] or file_hash(source) != row['features']['source_sha256']:
            raise ValueError('Source/feature file changed: '+key)
        with np.load(feature, allow_pickle=False) as z:
            duration = float(z['times'][-1])
        for variant in VARIANTS:
            outcome = row['results'][variant]; events = outcome['events']
            if outcome['pred'] != (events[-1]['label'] if events else None):
                raise ValueError('Final prediction differs from event history')
            if any(not 0 <= e['time'] <= duration+.002 for e in events): raise ValueError('Invalid event time')
            if any(a['time'] > b['time'] for a,b in zip(events,events[1:])): raise ValueError('Unordered events')
    recalculated = summarize(rows,len(expected))
    if any(recalculated[k] != report[k] for k in recalculated): raise ValueError('Saved metrics do not recompute')
    return contract, rows, report


def cut_rau(engine, root, rows):
    result = []
    r = engine.runtime; base = engine.base.word_head
    for row in rows:
        if row['item']['role'] != 'rau_train_pipeline_diagnostic': continue
        with np.load(root/'features'/(row['item']['video_id']+'.npz'),allow_pickle=False) as z:
            pose,wrist,context,times=(z[k].copy() for k in ('pose','wrist','context','times'))
        p,w = r.prepare_sign_sequence(pose,wrist)
        first,last = r.gesture_interval(p,w,context)
        candidate = (pose[first:last],wrist[first:last],context[first:last],times[first:last],
                     np.any(pose[first:last].reshape(-1,2,21,3)!=0,axis=(2,3)))
        infer,embed = InferenceMemo(base.infer),InferenceMemo(base.embed)
        outputs = {}
        for variant in VARIANTS:
            head = r.TemporalWordHead(list(base.labels),copy.deepcopy(base.config),infer,
                embed=embed,centers=base.centers,mean=base.mean,std=base.std,
                probability_fusion=ComponentFusion(base.probability_fusion,variant))
            scores,ready=head.predict([candidate])
            ix=np.argsort(-scores);target=head.labels.index('rau')
            outputs[variant]=dict(top=head.labels[int(ix[0])] if np.max(scores)>=0 else None,
                target_score=float(scores[target]),target_rank=int(np.flatnonzero(ix==target)[0])+1,
                target_ready=bool(ready[target]),diagnostic=plain(head.last_diagnostics),
                stream_pred=row['results'][variant]['pred'])
        result.append(dict(video_id=row['item']['video_id'],source=row['item']['source'],
            semantic_review=row['item']['semantic_review'],first=first,last=last,
            future_boundary_used=True,outputs=outputs))
    return dict(scope='TRAIN pipeline diagnostic; full-clip boundary uses future frames; not live accuracy',
        clips=len(result),summary={v:dict(
            cut_top1=sum(x['outputs'][v]['top']=='rau' for x in result),
            cut_qualified=sum(x['outputs'][v]['target_ready'] for x in result),
            stream_correct=sum(x['outputs'][v]['stream_pred']=='rau' for x in result),
            cut_correct_stream_not=sum(x['outputs'][v]['top']=='rau' and x['outputs'][v]['stream_pred']!='rau' for x in result))
            for v in VARIANTS},rows=result)


def make_reading(root, rows, report, cut):
    cal=[r for r in rows if r['item']['role']=='calibration_development']
    by_source={source:{v:metrics([r for r in cal if r['item']['source']==source],v)
                        for v in VARIANTS} for source in sorted({r['item']['source'] for r in cal})}
    critical={label:{v:metrics([r for r in cal if r['item']['label']==label],v)
                    for v in VARIANTS} for label in ['chào','nghe','nhìn','rau','bàn tay','cứu']}
    changes={}
    for variant in VARIANTS[1:]:
        gained=[];lost=[]
        for r in cal:
            label=r['item']['label'];a=r['results']['reference']['pred'];b=r['results'][variant]['pred']
            info=dict(video_id=r['item']['video_id'],label=label,source=r['item']['source'],before=a,after=b)
            if a!=label and b==label:gained.append(info)
            if a==label and b!=label:lost.append(info)
        a=report['calibration']['reference'];b=report['calibration'][variant]
        paired_lat=[]
        for r in cal:
            if r['results']['reference']['pred']!=r['item']['label'] or r['results'][variant]['pred']!=r['item']['label']:continue
            times=[[e['time'] for e in r['results'][v]['events'] if e['label']==r['item']['label']]
                   for v in ['reference',variant]]
            if all(times):paired_lat.append(times[1][0]-times[0][0])
        changes[variant]=dict(gained_videos=gained,lost_videos=lost,
            correct_delta=b['correct']-a['correct'],wrong_delta=b['wrong']-a['wrong'],
            wrong_events_delta=b['wrong_events']-a['wrong_events'],
            precision_delta=None if a['accepted_precision'] is None or b['accepted_precision'] is None else b['accepted_precision']-a['accepted_precision'],
            precision_floor_95_met=b['accepted_precision'] is not None and b['accepted_precision']>=.95,
            common_correct_first_event_delta_seconds=dict(videos=len(paired_lat),
                median=float(np.median(paired_lat)) if paired_lat else None))
    return dict(verified_complete=True,source_and_feature_hashes_verified=len(rows),
        reference_controls_passed=len(rows),development_only=True,deployment_eligible=False,
        real_background_measured=False,by_source=by_source,critical=critical,
        changes=changes,rau_cut_summary=cut['summary'])


def main():
    from .engine import Engine
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('root',type=Path);p.add_argument('--model-dir',type=Path,required=True)
    a=p.parse_args()
    contract,rows,report=verify(a.root)
    engine=Engine(a.model_dir)
    if identity(engine,'words')!=contract['model_identity']:raise ValueError('Model/runtime identity changed')
    cut=cut_rau(engine,a.root,rows)
    write_json(a.root/'rau-cut-diagnostic.json',cut)
    reading=make_reading(a.root,rows,report,cut)
    write_json(a.root/'verified-reading.json',reading)
    print(json.dumps(dict(verified_complete=True,clips=len(rows),rau_cut_summary=cut['summary'],
                         output=str(a.root.resolve())),ensure_ascii=True,indent=2))


if __name__=='__main__':main()
