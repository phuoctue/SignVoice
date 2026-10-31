"""Offline causal active-start window experiment. Never imported by the service.

One extra window extends the selected active interval with new measured frames.
No cached scores, prediction label continuity, shorter dwell or threshold search.
"""
import argparse
import ast
import __future__
import copy
import json
from pathlib import Path
import time
import types
import numpy as np
from .analyze_word_failures import new_session
from .diagnostic_replay import ATOL, RTOL, identity, plain, replay
from .evaluate_fixed_components import InferenceMemo, digest, file_hash, metrics, paired, write_json
from .review_fixed_components import verify


def signature(code):
    return (code.co_code,tuple(signature(x) if isinstance(x,types.CodeType) else x for x in code.co_consts),
        code.co_names,code.co_varnames,code.co_argcount,code.co_kwonlyargcount,code.co_freevars,
        code.co_cellvars,code.co_flags)


def metadata_predictor(source, original):
    """Compile metadata-only additions into an isolated instance method.

    Match the entire pristine compiled function before touching its AST. Compile,
    but never execute, the runtime module's imports, top-level code or main().
    """
    flags=0
    for name in __future__.all_feature_names:
        flags |= original.__code__.co_flags & getattr(__future__,name).compiler_flag
    def method_code(code):
        cls=next(x for x in code.co_consts if isinstance(x,types.CodeType) and x.co_name=='TemporalWordHead')
        return next(x for x in cls.co_consts if isinstance(x,types.CodeType) and x.co_name=='predict')
    pristine=method_code(compile(source,'<pristine runtime>','exec',flags=flags,dont_inherit=True))
    if signature(pristine)!=signature(original.__code__):raise ValueError('Unknown head implementation')
    tree=ast.parse(source)
    cls=next(x for x in tree.body if isinstance(x,ast.ClassDef) and x.name=='TemporalWordHead')
    method=next(x for x in cls.body if isinstance(x,ast.FunctionDef) and x.name=='predict')
    class AppendMetadata(ast.NodeTransformer):
        count=0
        def visit_Expr(self,node):
            call=node.value
            if (isinstance(call,ast.Call) and isinstance(call.func,ast.Attribute)
                and isinstance(call.func.value,ast.Name) and call.func.value.id=='batches'
                and call.func.attr=='append'):
                self.count+=1
                return [node,*ast.parse('_interval_metadata.append((float(clock[0]),float(clock[-1])))').body]
            return node
    transform=AppendMetadata();transform.visit(method)
    if transform.count!=2:raise ValueError('Unexpected batch construction')
    expected=ast.parse('best=int(np.argmax(np.where(eligible,quality,-np.inf))) if eligible.any() else int(np.argmax(quality))').body[0]
    matches=[i for i,x in enumerate(method.body) if ast.dump(x,include_attributes=False)==ast.dump(expected,include_attributes=False)]
    if len(matches)!=1:raise ValueError('Unknown window selection expression')
    pos=matches[0]+1
    method.body[pos:pos]=ast.parse('''self._selected_interval_metadata=_interval_metadata[best]
self._selected_eligible_metadata=bool(eligible[best])''').body
    method.body[:0]=ast.parse('''_interval_metadata=[]
self._selected_interval_metadata=None
self._selected_eligible_metadata=False''').body
    modified=method_code(compile(ast.fix_missing_locations(tree),'<observed head>','exec',flags=flags,dont_inherit=True))
    if modified.co_freevars:raise ValueError('Unexpected closure')
    return types.FunctionType(modified,original.__globals__,'predict')


class ActiveStartWindow:
    """A bounded extra candidate, always ending at the latest measured sample."""
    def __init__(self,session,runtime,predictor,enabled):
        self.session,self.runtime,self.enabled=session,runtime,enabled
        self.anchor=None
        self.stats=dict(added_windows=0,anchors_created=0,expiry_resets=0,buffer_resets=0)
        self.original_windows=session.buffer.windows
        self.original_clear=session.buffer.clear
        self.observed_predict=types.MethodType(predictor,session.recognizer.word_head)
        session.buffer.windows=self.windows
        session.buffer.clear=self.clear
        session.recognizer.word_head.predict=self.predict

    def clear(self):
        if self.anchor is not None:self.stats['buffer_resets']+=1
        self.anchor=None
        return self.original_clear()

    def windows(self):
        result=self.original_windows()
        frames=list(self.session.buffer.frames)
        if not self.enabled or self.anchor is None or not frames:return result
        start,created=self.anchor;now=frames[-1][0]
        ttl=float(self.session.buffer.gap_seconds)
        if now-created>ttl or frames[0][0]>start+1e-7:
            self.anchor=None;self.stats['expiry_resets']+=1;return result
        selected=[f for f in frames if f[0]>=start-1e-7]
        if (not selected or sum(bool(np.any(f[1])) for f in selected)<6
            or selected[-1][0]-selected[0][0]<.35):return result
        p=np.array([f[1] for f in selected]);w=np.array([f[2] for f in selected])
        times=np.array([f[0] for f in selected])
        observed=np.any(p.reshape(-1,2,21,3)!=0,axis=(2,3))
        if self.session.buffer.repair_gaps:p,w=self.runtime.repair_short_hand_gaps(p,w,times)
        # Avoid an exact duplicate before feature extraction, while keeping
        # measured masks distinct. The head also deduplicates prepared features.
        if any(np.array_equal(times,c[3]) and np.array_equal(observed,c[4]) for c in result):return result
        result.append((p,w,np.array([f[3] for f in selected]),times,observed))
        self.stats['added_windows']+=1
        return result

    def predict(self,candidates):
        result=self.observed_predict(candidates)
        head=self.session.recognizer.word_head
        if (self.enabled and self.anchor is None and head._selected_eligible_metadata
            and np.any(result[1]) and self.session.buffer.frames):
            self.anchor=(head._selected_interval_metadata[0],self.session.buffer.frames[-1][0])
            self.stats['anchors_created']+=1
        return result


def outcome(session,stats):
    return dict(pred=session.events[-1]['label'] if session.events else None,
        events=plain(session.events),window_stats=copy.deepcopy(stats))


def run_clip(engine,arrays,saved,predictor):
    h=engine.base.word_head;infer,embed=InferenceMemo(h.infer),InferenceMemo(h.embed)
    sessions=[new_session(engine,infer,embed) for _ in range(3)]
    controls=[None,ActiveStartWindow(sessions[1],engine.runtime,predictor,False),
        ActiveStartWindow(sessions[2],engine.runtime,predictor,True)]
    snapshots=[]
    # Run the metadata-only null branch before the candidate. Neither may touch
    # the reference's model or state; only identical neural inputs share memo.
    results={}
    for name,session,adapter in zip(('reference','metadata_null','anchored'),sessions,controls):
        for index,(p,w,now,c) in enumerate(zip(*arrays)):
            session.update(p,w,float(now),context=c)
            scores=session.decision.smoothed
            if name=='reference':snapshots.append((None if scores is None else scores.copy(),plain(session.output)))
            elif name=='metadata_null':
                wanted,output=snapshots[index]
                if scores is None or wanted is None:
                    if scores is not None or wanted is not None:raise RuntimeError('Null score mismatch')
                elif not np.allclose(scores,wanted,atol=ATOL,rtol=RTOL):raise RuntimeError('Metadata changed scores')
                if plain(session.output)!=output:raise RuntimeError('Metadata changed output')
        results[name]=outcome(session,{} if adapter is None else adapter.stats)
    if results['reference']['events']!=saved['events']:raise RuntimeError('Reference differs from frozen run')
    if results['metadata_null']['events']!=saved['events']:raise RuntimeError('Metadata null event mismatch')
    return dict(reference=results['reference'],anchored=results['anchored'],
        null_control_passed=True,input_frames_controlled=len(snapshots))


def report_rows(rows):
    reference=metrics(rows,'reference');candidate=metrics(rows,'anchored')
    gained=[];lost=[];changed=[]
    for row in rows:
        item=row['item'];truth=item['label']
        a=row['results']['reference']['pred'];b=row['results']['anchored']['pred']
        info=dict(video_id=item['video_id'],word=truth,source=item['source'],before=a,after=b)
        if a!=truth and b==truth:gained.append(info)
        if a==truth and b!=truth:lost.append(info)
        if row['results']['reference']['events']!=row['results']['anchored']['events']:changed.append(info)
    paired_report=paired(rows,'anchored')
    ci=paired_report['macro_recall_delta_ci95']
    critical=['chào','nghe','nhìn','rau','bàn tay','cứu']
    by_critical={w:{name:metrics([r for r in rows if r['item']['label']==w],name)
        for name in ('reference','anchored')} for w in critical}
    checks=dict(correct_increased=candidate['correct']>reference['correct'],
        macro_ci_positive=ci is not None and ci[0]>0,
        precision_floor_met=candidate['accepted_precision'] is not None and candidate['accepted_precision']>=.95,
        precision_not_lower=candidate['accepted_precision'] is not None and reference['accepted_precision'] is not None
            and candidate['accepted_precision']>=reference['accepted_precision'],
        wrong_clips_not_increased=candidate['wrong']<=reference['wrong'],
        wrong_events_not_increased=candidate['wrong_events']<=reference['wrong_events'],
        duplicate_events_not_increased=candidate['consecutive_duplicate_events']<=reference['consecutive_duplicate_events'],
        represented_critical_not_lost=all(by_critical[w]['anchored']['correct']>=by_critical[w]['reference']['correct'] for w in critical))
    return dict(reference=reference,anchored=candidate,checks=checks,
        development_screen_passed=all(checks.values()),deployment_eligible=False,
        real_background_measured=False,independent_webcam_measured=False,
        paired=paired_report,gained_videos=gained,lost_videos=lost,event_changed_videos=changed,
        critical=by_critical,missing_critical=[w for w in critical if not by_critical[w]['reference']['videos']],
        added_windows=sum(r['results']['anchored']['window_stats']['added_windows'] for r in rows))


def webcam_probe(engine,capture,predictor):
    if identity(engine,'words')!=capture['worker_identity']:raise ValueError('Webcam identity changed')
    if capture.get('truncated') or any(m.get('worker_diagnostic',{}).get('truncated') for m in capture['messages']):
        raise ValueError('Truncated webcam recording')
    rows=[r for m in capture['messages'] for r in m.get('worker_diagnostic',{}).get('records',[])]
    control=new_session(engine);null=ActiveStartWindow(control,engine.runtime,predictor,False)
    checked=replay(control,rows)
    if not checked['passed']:raise ValueError('Webcam metadata null failed')
    session=new_session(engine);adapter=ActiveStartWindow(session,engine.runtime,predictor,True)
    generation=None
    for row in rows:
        if generation!=row['generation']:
            session.recognizer.set_mode(row['mode']);session.reset();generation=row['generation']
        for item in row['inputs']:
            session.update(np.asarray(item['pose'],np.float32),np.asarray(item['wrist'],np.float32),
                item['time'],allow_prediction=item['allow_prediction'],context=np.asarray(item['context'],np.float32))
    return dict(scope='previously viewed webcam development recording, not independent accuracy',
        null_control=checked,reference_events=plain(control.events),candidate_events=plain(session.events),
        candidate_stats=adapter.stats)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--model-dir',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--smoke',action='store_true')
    p.add_argument('--webcam',type=Path)
    a=p.parse_args()
    old,rows,_=verify(a.input)
    from .engine import Engine
    engine=Engine(a.model_dir)
    before=identity(engine,'words')
    if before!=old['model_identity']:raise ValueError('Model/runtime identity changed')
    source=Path(__file__).with_name('model_runtime.py').read_text(encoding='utf-8')
    predictor=metadata_predictor(source,type(engine.base.word_head).predict)
    cal=[r for r in rows if r['item']['role']=='calibration_development']
    if a.smoke:
        cal=sum(([r for r in cal if ('none' if r['results']['reference']['pred'] is None else
            'correct' if r['results']['reference']['pred']==r['item']['label'] else 'wrong')==state][:3]
            for state in ('correct','none','wrong')),[])
    contract=dict(version=1,smoke=a.smoke,code_sha256=file_hash(__file__),model_identity=before,
        dependencies={f:file_hash(Path(__file__).with_name(f)) for f in ('analyze_word_failures.py',
            'diagnostic_replay.py','evaluate_fixed_components.py','review_fixed_components.py')},
        input_contract_sha256=digest(old),cohort_ids=[r['item']['video_id'] for r in cal],
        change='One active-start window extending only fresh buffer measurements, TTL equals tracking_gap_seconds; no label retention',
        thresholds_changed=False,dwell_changed=False,cadence_changed=False,model_changed=False,
        real_background_measured=False,automatic_promotion=False,
        webcam_sha256=file_hash(a.webcam) if a.webcam else None,
        development_criteria='more correct, paired macro CI lower>0, precision>=max(.95,reference), no increase wrong clips/events/duplicates or lost represented critical counts',
        smoke_scope='engineering controls only')
    a.output.mkdir(parents=True,exist_ok=True)
    path=a.output/'contract.json'
    if path.exists() and json.loads(path.read_text(encoding='utf-8'))!=contract:raise ValueError('Different contract; use a new folder')
    write_json(path,contract)
    done={};journal=a.output/'results.jsonl'
    if journal.exists():
        for line in journal.read_text(encoding='utf-8').splitlines():
            row=json.loads(line);key=row['item']['video_id']
            if key in done or row['contract_sha256']!=digest(contract):raise ValueError('Invalid journal')
            done[key]=row
    expected={r['item']['video_id']:r for r in cal}
    if any(k not in expected or row['item']!=expected[k]['item'] for k,row in done.items()):raise ValueError('Resumed cohort changed')
    start=time.perf_counter()
    for saved in cal:
        key=saved['item']['video_id']
        if key in done:continue
        with np.load(a.input/'features'/(key+'.npz'),allow_pickle=False) as z:
            arrays=tuple(z[k].copy() for k in ('pose','wrist','times','context'))
        results=run_clip(engine,arrays,saved['results']['reference'],predictor)
        row=dict(contract_sha256=digest(contract),item=saved['item'],features=saved['features'],results=results)
        with journal.open('a',encoding='utf-8') as f:f.write(json.dumps(plain(row),ensure_ascii=False,allow_nan=False)+'\n');f.flush()
        done[key]=row
        write_json(a.output/'status.json',dict(processed=len(done),expected=len(cal),complete=len(done)==len(cal)))
        if len(done)%25==0 or len(done)==len(cal):print(f'{len(done)}/{len(cal)}',flush=True)
    ordered=[done[r['item']['video_id']] for r in cal]
    report=report_rows(ordered)
    report['excluding_unverified_chao_khangcn']=report_rows([r for r in ordered if not r['item']['unverified_chao_khangcn']])
    report['by_source']={s:report_rows([r for r in ordered if r['item']['source']==s]) for s in sorted({r['item']['source'] for r in ordered})}
    report.update(complete=len(done)==len(cal),engineering_smoke_only=a.smoke,
        null_controls_passed=len(done),elapsed_seconds=time.perf_counter()-start)
    if a.webcam:report['webcam_probe']=webcam_probe(engine,json.loads(a.webcam.read_text(encoding='utf-8')),predictor)
    if identity(engine,'words')!=before:raise RuntimeError('Experiment mutated original model/policy')
    write_json(a.output/'comparison.json',report)
    print(json.dumps(dict(complete=report['complete'],reference=report['reference'],anchored=report['anchored'],
        checks=report['checks'],added_windows=report['added_windows'],webcam=report.get('webcam_probe')),ensure_ascii=True),flush=True)


if __name__=='__main__':main()
