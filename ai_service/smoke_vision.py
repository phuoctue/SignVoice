"""Exercise the real LM Studio image endpoint; not an accuracy evaluation."""
import json
from pathlib import Path
import cv2
from .vision import ReferenceLibrary,verify_images


def main():
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--reference-control',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    word=json.loads((root/'word_temporal_config.json').read_text(encoding='utf-8'))
    glyph=json.loads((root/'recognizer_config.json').read_text(encoding='utf-8'))
    ids=set(word.get('train_video_ids',[]))|set(glyph.get('train_video_ids',[]))
    refs=ReferenceLibrary(root/'SignVoice_Dataset_ToanBo_MoRong_2026-10-16.zip',Path(__file__).parent/'.cache/vision_refs',ids)
    frames=[];cap=cv2.VideoCapture(str(Path.home()/'Downloads/Recording 2026-10-17 202335.mp4'))
    for sec in (.1,.5,.9,1.3):
        cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);ok,image=cap.read();assert ok
        h,w=image.shape[:2];frames.append(cv2.flip(image[round(h*.113):round(h*.478),round(w*.03):round(w*.985)],1))
    cap.release()
    candidates=['ch\u00e0o','rau','b\u00e0n tay']
    if args.reference_control:frames=refs.get('rau')
    report=verify_images(frames,candidates,refs)
    report.update(accuracy_measured=False,training_reference_ids_verified=True,
        candidate_references={label:len(refs.get(label)) for label in candidates})
    report['reference_control']=args.reference_control
    output=Path(__file__).parent/'reports/camera_20261017'/('vision_reference_control.json' if args.reference_control else 'vision_smoke.json')
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=True))


if __name__=='__main__':main()
