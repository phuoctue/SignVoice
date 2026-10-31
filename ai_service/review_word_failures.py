"""Validate a completed diagnosis and write its descriptive, non-promotional report."""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path
import numpy as np
from .evaluate_fixed_components import digest, file_hash, write_json

DESCRIPTIONS = {
    'final_correct':'Chốt cuối đúng',
    'target_emitted_then_other_label':'Từng phát đúng rồi nhãn khác thay thế',
    'mature_target_without_completed_event':'Candidate đúng đủ dwell nhưng không có sự kiện hoàn tất',
    'qualified_target_run_shorter_than_dwell':'Candidate đúng reliable, chuỗi ngắn hơn dwell',
    'head_ready_but_no_reliable_target_decision':'Head sẵn sàng nhưng chưa có decision đúng reliable',
    'eligible_target_window_not_confirmed':'Có cửa sổ đúng eligible nhưng chưa được head chọn để chốt',
    'target_top_but_head_gates_not_met':'Từng đứng đầu cửa sổ, chưa sẵn sàng ở head được chọn',
    'target_never_top_in_live_windows':'Nhãn đúng chưa từng đứng đầu cửa sổ live',
    'no_usable_live_inference':'Không có cửa sổ inference live hợp lệ',
}


def review(root, original_root):
    contract=json.loads((root/'contract.json').read_text(encoding='utf-8'))
    report=json.loads((root/'summary.json').read_text(encoding='utf-8'))
    if contract['smoke'] or not report['complete']: raise ValueError('Not a completed full diagnosis')
    if contract['tool_sha256']!=file_hash(Path(__file__).with_name('analyze_word_failures.py')):
        raise ValueError('Diagnostic tool changed after the registered run')
    if any(file_hash(Path(__file__).with_name(name))!=value
           for name,value in contract['dependency_sha256'].items()):
        raise ValueError('Diagnostic dependency changed after the registered run')
    old_contract=json.loads((original_root/'contract.json').read_text(encoding='utf-8'))
    if digest(old_contract)!=contract['input_contract_sha256']: raise ValueError('Input contract mismatch')
    original={r['item']['video_id']:r for line in (original_root/'results.jsonl').read_text(encoding='utf-8').splitlines()
              if (r:=json.loads(line))['item']['role']=='calibration_development'}
    rows=[json.loads(line) for line in (root/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    ids=[r['item']['video_id'] for r in rows]
    if len(ids)!=297 or len(set(ids))!=297 or set(ids)!=set(original): raise ValueError('Incomplete/duplicate/changed cohort')
    for row in rows:
        key=row['item']['video_id'];saved=original[key]
        if row['item']!=saved['item'] or row['features']!=saved['features']:
            raise ValueError('Changed source metadata')
        if row['diagnostic_contract_sha256']!=digest(contract): raise ValueError('Changed diagnostic contract')
        if not all(row['control'][k] for k in ('all_input_scores_equal','all_input_outputs_equal','frozen_events_equal')):
            raise ValueError('Failed trace control')
        if row['events']!=saved['results']['reference']['events']:
            raise ValueError('Reference events changed')
        if [e for s in row['steps'] for e in s['emitted']]!=row['events']:
            raise ValueError('Lost/duplicate event in step trace')
        for folder,field,suffix in [('features','feature_sha256','.npz'),('sources','source_sha256','.mp4')]:
            if file_hash(original_root/folder/(key+suffix))!=row['features'][field]:
                raise ValueError('Changed cached input')
    categories=Counter(r['classification']['category'] for r in rows)
    if dict(categories)!=report['overall']['categories']: raise ValueError('Category totals mismatch')
    none=sum(not r['events'] for r in rows)
    wrong=sum(bool(r['events']) and r['events'][-1]['label']!=r['item']['label'] for r in rows)
    correct=len(rows)-none-wrong
    if (correct,wrong,none)!=(171,8,118): raise ValueError('Reference aggregate changed')
    failed=[r for r in rows if r['classification']['category']!='final_correct']
    qualified_cut=[r for r in rows if r['cut']['target_ready']]
    failed_qualified_cut=[r for r in qualified_cut if r in failed]
    wrong_events=[];correct_event_scores=[]
    for r in rows:
        for step in r['steps']:
            for event in step['emitted']:
                evidence=dict(video_id=r['item']['video_id'],truth=r['item']['label'],
                    prediction=event['label'],time=event['time'],
                    score=step['decision']['score'],margin=step['decision']['margin'],
                    final_correct=r['classification']['category']=='final_correct')
                if event['label']!=r['item']['label']:wrong_events.append(evidence)
                else:correct_event_scores.append(evidence['score'])
    if len(wrong_events)!=16 or len(report['wrong_event_evidence'])!=16:raise ValueError('Wrong event count mismatch')
    if any(r['classification']['unexplained_mature_target_times'] for r in rows):
        raise ValueError('Unexplained mature decision must be investigated before conclusion')
    result=dict(verified_complete=True,clips=len(rows),correct=correct,wrong=wrong,none=none,
        failed_cut_qualified=len(failed_qualified_cut),
        failed_cut_qualified_categories=dict(Counter(r['classification']['category'] for r in failed_qualified_cut)),
        failed_cut_top_correct=sum(r['classification']['cut_top_correct'] for r in failed),
        missing_input_clips=[dict(video_id=r['item']['video_id'],label=r['item']['label'],
            reason=r['cut'].get('unavailable_reason')) for r in rows if not r['cut']['available']],
        failed_affected_words=len({r['item']['label'] for r in failed}),
        categories={k:dict(count=v,failed_fraction=v/len(failed)) for k,v in categories.items() if k!='final_correct'},
        dominant_failed_category=next((k for k,v in categories.items() if k!='final_correct' and v/len(failed)>.5),None),
        wrong_events=wrong_events,
        wrong_event_score_range=[min(e['score'] for e in wrong_events),max(e['score'] for e in wrong_events)],
        correct_event_score_median=float(np.median(correct_event_scores)),
        wrong_event_score_median=float(np.median([e['score'] for e in wrong_events])),
        duplicate_events=sum(r['classification']['consecutive_duplicate_events'] for r in rows),
        report_contract_sha256=digest(contract),deployment_eligible=False)
    return report,rows,result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('root',type=Path);p.add_argument('--original',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();summary,rows,verified=review(a.root,a.original)
    write_json(a.root/'verified-reading.json',verified)
    with (a.root/'per-video-failures.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=['video_id','word','source','final_pred','cut_available',
            'cut_top','cut_qualified','category','maximum_candidate_elapsed','wrong_events'])
        writer.writeheader()
        for r in rows:
            writer.writerow(dict(video_id=r['item']['video_id'],word=r['item']['label'],source=r['item']['source'],
                final_pred=r['events'][-1]['label'] if r['events'] else '',cut_available=r['cut']['available'],
                cut_top=r['cut']['top'],cut_qualified=r['cut']['target_ready'],
                category=r['classification']['category'],
                maximum_candidate_elapsed=r['classification']['maximum_candidate_elapsed'],
                wrong_events=r['classification']['wrong_events']))
    overall=summary['overall']
    lines=['# Chẩn đoán chung cho 181 từ — 22/10/2026','',
        '**Đã kiểm đủ 297 clip phát triển thuộc 157/181 từ; 24 từ thiếu calibration. Không thay model hoặc policy trong app.**','',
        f"Đối chứng khớp {len(rows)}/{len(rows)} clip ở mọi đầu vào, output và sự kiện; còn khớp reference đã đóng băng. Kết quả stream giữ nguyên: {verified['correct']} đúng, {verified['wrong']} sai, {verified['none']} không chốt. Có {verified['failed_affected_words']} từ có ít nhất một clip không chốt đúng cuối cùng.",'',
        '## Các tầng lỗi','',
        f"Word head clip cắt xếp đúng đầu {overall['cut_correct']}/297; sẵn sàng nhãn đúng {overall['cut_qualified']}/297. Có {overall['cut_unavailable']} clip không đủ đầu vào để chạy clip cắt. Ranh giới clip cắt dùng thông tin tương lai và chưa chạy dwell, nên không coi là accuracy live hoặc số VAL của notebook.",'',
        '| Trạng thái quan sát trên 126 clip không chốt đúng cuối cùng | Clip | Tỷ lệ |',
        '|---|---:|---:|']
    for key,value in verified['categories'].items():
        lines.append(f"| {DESCRIPTIONS[key]} | {value['count']} | {100*value['failed_fraction']:.1f}% |")
    lines+=['',
        ('Không có nhóm nào vượt 50%; lỗi hỗn hợp theo định nghĩa chốt trước.' if verified['dominant_failed_category'] is None else
         'Nhóm chiếm hơn 50% theo định nghĩa chốt trước: '+DESCRIPTIONS[verified['dominant_failed_category']]+'.'),'',
        f"Trong nhóm thất bại, {verified['failed_cut_top_correct']} clip xếp nhãn đúng đầu ở clip cắt; {verified['failed_cut_qualified']} clip còn đủ điều kiện head ở clip cắt. Không quy toàn bộ nhóm này cho dwell: bảng phân rã trong verified-reading.json giữ từng trạng thái riêng.",'',
        'Nhóm “từng đứng đầu cửa sổ, chưa sẵn sàng ở head được chọn” có thể gồm ngưỡng, mask, ưu tiên slot gốc và cạnh tranh giữa cửa sổ. Không đọc nó thành chỉ một nguyên nhân. Nhóm “có cửa sổ đúng eligible” là eligibility thực tế sau ưu tiên slot gốc; không dựng oracle từ điểm cực đại từng nhãn.','',
        f"Trong {overall['failed_with_target_top']} clip thất bại có nhãn đúng đứng đầu decision ít nhất một bước inference, tỷ lệ lý do đã được chuẩn hóa trong từng clip, rồi trung bình:",'',
        '| Tập lý do cùng xuất hiện ở bước decision nhãn đúng | Trung bình tỷ lệ bước trong clip |',
        '|---|---:|']
    for reason,fraction in overall['mean_clip_normalized_blocker_fraction'].items():
        lines.append(f'| {reason} | {100*fraction:.2f}% |')
    lines+=['',
        '`qualified` nghĩa là bước đã qua cổng điểm/margin/readiness, không đồng nghĩa đã phát sự kiện. Startup chưa inference bị loại. Các tỷ lệ có điều kiện này không đại diện cho toàn bộ 126 clip thất bại, và không tự xác định nguyên nhân của clip chưa từng đứng đầu decision.','',
        '## Kiểm tra phía nhận nhầm','',
        f"Có {len(verified['wrong_events'])} sự kiện sai, không chỉ {verified['wrong']} clip sai cuối cùng. Điểm decision của sự kiện sai nằm trong [{verified['wrong_event_score_range'][0]:.4f}; {verified['wrong_event_score_range'][1]:.4f}]; trung vị {verified['wrong_event_score_median']:.4f}, so với {verified['correct_event_score_median']:.4f} của sự kiện đúng. Đây chỉ là mô tả tại thời điểm phát; chưa phải replay ngưỡng mới.",'',
        f"Không có candidate đúng đủ dwell mà thiếu confirmed không giải thích được. Có {verified['duplicate_events']} sự kiện trùng nhãn liên tiếp; chưa thể xác định tất cả là phát lặp sai vì clip nguồn không có ranh giới số lần ký độc lập.",'',
        'Mọi sự kiện sai giữ video ID, nhãn nguồn, nhãn phát, thời gian, score và margin trong verified-reading.json. Nhãn chào KhangCN chưa xác minh được báo riêng trong summary.json; không tự sửa nhãn theo model.','',
        '## Đầu vào thiếu','']
    for r in verified['missing_input_clips']:lines.append(f"- {r['label']} — `{r['video_id']}`: {r['reason']}. Vẫn giữ trong mẫu số stream.")
    lines+=['','## Đọc kết quả khi cân nhắc đổi model','',
        'Model hiện tại chưa đáp ứng yêu cầu webcam của người dùng. Tuy nhiên, số 255/297 xếp đúng ở clip cắt so với 171/297 chốt đúng stream cho thấy cần giải quyết cả nhận diện theo thời gian và cách lấy đầu vào; không đủ bằng chứng quy toàn bộ lỗi cho dung lượng kiến trúc. Clip cắt dùng tương lai nên chênh lệch này không phải mức tăng live có thể lấy lại chắc chắn.','',
        f"Trong {verified['failed_cut_qualified']} clip thất bại nhưng đủ điều kiện ở clip cắt, {verified['failed_cut_qualified_categories'].get('qualified_target_run_shorter_than_dwell',0)} có candidate đúng reliable nhưng chưa đủ dwell ở stream. Không giảm dwell hàng loạt: có sự kiện sai đạt 0,9624 và chưa có nền thật; score cao không phải bảo đảm đúng.",'',
        'Hướng tiếp theo: (1) xử lý chất lượng đầu vào và khả năng giữ dự đoán ổn định trong cửa sổ live bằng một thay đổi chung, kiểm cả clip được và mất trên cohort cố định; (2) nếu thử checkpoint/kiến trúc mới, kiểm nhãn và schema feature, checksum, đặc biệt không để các clip đánh giá đã nằm trong TRAIN của candidate; (3) so cả stream, sự kiện sai và latency thiết bị thật, rồi xác nhận trên webcam/người/nền độc lập. Chưa chọn tên kiến trúc mới theo một vài clip và chưa train lại từ báo cáo này.','',
        'Ba nhánh thay thế đã thử trong FIXED_COMPONENT_RESULTS_20261022.md chưa đủ điều kiện thay cấu hình hiện tại. Giữ nó làm mốc so sánh không đồng nghĩa đã công nhận chất lượng sản phẩm đạt.','',
        '## Tệp và phạm vi','',
        f"- Bảng đủ 181 từ: `{a.root/'all-181-words-failures.csv'}`.",
        f"- Bảng từng clip: `{a.root/'per-video-failures.csv'}`.",
        f"- Trace, hợp đồng và đối chứng: `{a.root}`.",
        '- Giao thức: `docs/ALL_WORD_FAILURE_PROTOCOL_20261022.md`.',
        '- Triển khai công cụ: `ai_service/analyze_word_failures.py`, `ai_service/review_word_failures.py`.','',
        'Chỉ là dữ liệu phát triển đã xem nhiều lần; người ký và nhãn chưa được thẩm định toàn bộ. Chưa đo nền thật hoặc webcam độc lập. Không suy diễn số clip từ nguồn thành độ chính xác camera điện thoại, không tính false accept/phút bằng 0, không chọn ngưỡng/model tự động. Không có kết quả được chứng minh cho 24 từ thiếu calibration.','']
    a.report.parent.mkdir(parents=True,exist_ok=True)
    a.report.write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps(verified,ensure_ascii=True,indent=2))


if __name__=='__main__':main()
