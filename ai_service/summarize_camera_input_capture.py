"""Summarize existing camera-input and component reports without new inference."""
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path
import numpy as np


def summarize(capture, components, input_report, config):
    records=[r for m in capture['messages'] for r in m.get('worker_diagnostic',{}).get('records',[])]
    predictions=[s for s in components['steps'] if s.get('inference_ran')]
    names=config['labels']; targets=['chào','nghe','nhìn','rau']
    timeline=[]
    for step in predictions:
        window=step['windows'][step['selected']]
        timeline.append(dict(time=step['time'], start=window['interval']['start'],end=window['interval']['end'],
            selected_word=step['diagnostic']['selected_word'],score=step['diagnostic']['score'],
            ready=step['diagnostic']['confirmation_ready'],rejection_reasons=step['diagnostic']['rejection_reasons'],
            tcn_top=window['tcn']['top3'][0],embedding_probability_top=window['embedding_probability']['top3'][0],
            target_fused={name:window['fused']['targets'][name] for name in targets}))
    peaks={}
    for name in targets:
        ix=names.index(name)
        available=[r for r in records if r.get('scores') is not None]
        peak=max(available,key=lambda r:r['scores'][ix])
        peaks[name]=dict(score=peak['scores'][ix],time=peak['inputs'][-1]['time'],
            top_at_peak=names[int(np.argmax(peak['scores']))],
            interpretation='Maximum across entire capture, not independently annotated gesture interval or accuracy')
    frames=input_report['snapshots']
    disagreements=[dict(timestamp_ms=f['timestamp_ms'],browser_hands=f['raw_hands'],
        cpu_image_hands=f['cpu_image_vs_browser_raw']['second_hands']) for f in frames
        if f['raw_hands']!=f['cpu_image_vs_browser_raw']['second_hands']]
    distances=[pair['median_xy_width_units']*f['width'] for f in frames
        for pair in f['cpu_image_vs_browser_raw']['pairs']]
    local=[m for m in capture['messages'] if m.get('kind')=='local' and isinstance(m.get('raw_hands'),int)]
    return dict(source_sha256=components['capture_sha256'],input_parity=input_report['feature_conversion'],
        worker_replay=components['replay_control'],snapshots=len(frames),worker_inputs=sum(len(r['inputs']) for r in records),
        worker_batches=len(records),input_seconds=[min(i['time'] for r in records for i in r['inputs']),
            max(i['time'] for r in records for i in r['inputs'])],unique_inferences=len(predictions),
        ready_predictions=sum(bool(s['diagnostic']['confirmation_ready']) for s in predictions),
        rejection_counts=dict(collections.Counter(reason for s in predictions for reason in s['diagnostic']['rejection_reasons'])),
        target_smoothed_peaks=peaks,final_events=records[-1]['events'],
        sampled_hand_count_agreement=dict(agree=len(frames)-len(disagreements),total=len(frames),disagreements=disagreements),
        matched_hands=len(distances),cpu_vs_browser_median_per_hand_xy_pixel_error=float(np.median(distances)),
        raw_hand_counts=dict(collections.Counter(str(m['raw_hands']) for m in local)),
        local_filter_rejections=sum(m.get('rejected_hands',0) for m in local),
        worker_overruns=max(r['observation_overruns'] for r in records),
        preparation_control=components['prepare_sequence_numerical_control'],
        webcam_accuracy_measured=False,policy_changed=False,
        cautions=['Maximum target scores span the entire capture; intended sign labels/time boundaries are not independently verified.',
            'No active-phase hand recall can be computed from sampled PNGs alone.',
            'CPU IMAGE vs browser VIDEO differences are descriptive, not detector ground truth.',
            'PNG recording adds workload; timing is not a normal-mode phone benchmark.',
            'Observed XYZ parity reuses recorded face context; not a full pixel-to-feature equivalence proof.']),timeline


def main():
    import sys
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('capture',type=Path);p.add_argument('--folder',required=True,type=Path)
    p.add_argument('--model-dir',required=True,type=Path);args=p.parse_args()
    raw=args.capture.read_bytes();capture=json.loads(raw)
    components=json.loads((args.folder/'components.json').read_bytes())
    inputs=json.loads((args.folder/'input-report.json').read_bytes())
    if not (hashlib.sha256(raw).hexdigest()==components['capture_sha256']==inputs['recording_sha256']):
        raise ValueError('Reports refer to different recordings')
    config=json.loads((args.model_dir/'recognizer_config.json').read_bytes())
    summary,timeline=summarize(capture,components,inputs,config)
    (args.folder/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
    with (args.folder/'prediction-timeline.csv').open('w',encoding='utf-8-sig',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=['time','start','end','word','score','ready','rejections',
            'tcn_top','embedding_top',*['fused_'+w for w in summary['target_smoothed_peaks']]])
        writer.writeheader()
        for item in timeline:
            writer.writerow(dict(time=item['time'],start=item['start'],end=item['end'],word=item['selected_word'],
                score=item['score'],ready=item['ready'],rejections=';'.join(item['rejection_reasons']),
                tcn_top=item['tcn_top']['label'],embedding_top=item['embedding_probability_top']['label'],
                **{'fused_'+k:v['score'] for k,v in item['target_fused'].items()}))
    print(json.dumps(summary,ensure_ascii=False,indent=2,allow_nan=False))


if __name__=='__main__':main()
